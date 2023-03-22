require 'dotenv/load'
require 'byebug'

require 'sqlite3'
require 'sequel'
Sequel::Model.plugin :timestamps
DB = Sequel.connect('sqlite://database.db')

require 'sinatra'
require 'sinatra/reloader' if development?

require 'mail'
require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'openai'

require './email'
require './draft'

# Something is measuring the bytesize of the messages to then put in the Content-Length header, but no such method exists. Don't really care for it so just hacking it
class Google::Apis::GmailV1::Message
  def bytesize
    1
  end
end

CLIENT_ID = Google::Auth::ClientId.new(ENV.fetch('GOOGLE_CLIENT_ID'), ENV.fetch('GOOGLE_SECRET'))
TOKEN_STORE = Google::Auth::Stores::FileTokenStore.new(file: 'tokens.yaml')
GOOGLE_AUTHORIZER = Google::Auth::WebUserAuthorizer.new(CLIENT_ID, [Google::Apis::GmailV1::AUTH_GMAIL_MODIFY], TOKEN_STORE)

get '/' do
  @drafts = Draft.all
  erb :index
end

get '/google_oauth' do
  redirect to(GOOGLE_AUTHORIZER.get_authorization_url(login_hint: request['login_hint'], request: request))
end

get '/oauth2callback' do
  credentials = GOOGLE_AUTHORIZER.get_credentials_from_code(code: request['code'], scope: request['scope'], user_id: 1, base_url: 'http://localhost:4567/google_oauth')
  draft_response_emails(credentials)
end

def draft_response_emails(credentials)
  drafts_created = []

  service = Google::Apis::GmailV1::GmailService.new
  service.authorization = credentials

  result = service.list_user_messages('me', q: "is:inbox", max_results: 5, label_ids: ['IMPORTANT'])

  result.messages.each do |message|
    next if Email.where(gmail_id: message.id).count > 0

    msg = service.get_user_message('me', message.id)

    create_draft_response(service, msg)
  end
end

def create_draft_response(service, message)
  # Extract the required information from the message
  thread_id = message.thread_id
  subject = message.payload.headers.find { |header| header.name == 'Subject' }.value
  from = message.payload.headers.find { |header| header.name == 'From' }.value
  cc = message.payload.headers.find { |header| header.name == 'Cc' }&.value
  
  email = Email.create(gmail_id: message.id, subject: subject, from: from, cc: cc, thread_id: thread_id)

  parts = message.payload.parts
  
  return if parts.nil? || parts.empty?

  text_part = parts.find { |part| part.mime_type == 'text/plain' }
  
  # Newsletters are `text/html` so we can skip them
  return if text_part.nil?

  email_content = text_part.body.data

  email.update(body: email_content)

  message = ::Mail.new
  message.to = [from, cc].flatten.compact.join(', ')
  message.subject = subject
  message.body = generate_email_response(email_content, email.id)
  message.content_type = 'text/plain; charset=UTF-8'

  # Create the draft
  draft = Google::Apis::GmailV1::Draft.new(
    message: Google::Apis::GmailV1::Message.new(
      raw: message.to_s, 
      thread_id: thread_id
    )
  )

  # Save the draft to Gmail
  service.create_user_draft('me', draft)
end

def generate_email_response(content, email_id)
  client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_KEY'), organization_id: ENV.fetch('OPENAI_ORG'))

  prompt = <<~MULTI_LINE_STRING
    You're an email writing assistant. You pre-draft emails that then I'll review before sending. 
    I'm technical and usually don't use complicated sentences or words. I write concise emails and stick to addressing the sender's point without digressing too much. 
    Use a writing style similar to Paul Graham or Ben Horowitz.
    If the recipient asks to schedule, I respond asking to suggest times that work for them, or to pick one from my Calendly: https://calendly.com/alessio-decibel/catchup-call
    You do not need to add my email signature.

    This is an email thread, it has both my emails (the ones from alessio@decibel.vc) and other people's:

    #{content}

    What should I respond? If you want to say something but don't know the details, add FILL_IN_HERE where you want me to edit it
  MULTI_LINE_STRING

  response = client.chat(
    parameters: {
        model: "gpt-3.5-turbo", # Required.
        messages: [{ role: "user", content: prompt}], # Required.
        temperature: 0.5,
    })

  result = response.dig("choices", 0, "message", "content").sub(/^\n*/, '')

  Draft.create(email_id: email_id, result: result.to_s, prompt: prompt.to_s)

  result
end