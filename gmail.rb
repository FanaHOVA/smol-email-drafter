require 'dotenv/load'
require 'byebug'

require 'sinatra'
require 'sinatra/reloader' if development?

require 'googleauth/stores/file_token_store'
require 'mail'

require 'google/apis/gmail_v1'
require 'googleauth'
require 'openai'

CLIENT_ID = Google::Auth::ClientId.new(ENV.fetch('GOOGLE_CLIENT_ID'), ENV.fetch('GOOGLE_SECRET'))
TOKEN_STORE = Google::Auth::Stores::FileTokenStore.new(file: 'tokens.yaml')
AUTHORIZER = Google::Auth::WebUserAuthorizer.new(CLIENT_ID, [Google::Apis::GmailV1::AUTH_GMAIL_MODIFY], TOKEN_STORE)

get '/' do
  erb :index
end

get '/oauth2callback' do
  credentials = AUTHORIZER.get_credentials_from_code(code: request['code'], scope: request['scope'], user_id: 1, base_url: ENV.fetch('BASE_URL'))
  redirect to("/draft_emails?credentials=#{credentials}")
end

get '/draft_emails' do
  list_emails(request['credentials'])
end

def list_emails(credentials)
  drafts_created = []
  
  service = Google::Apis::GmailV1::GmailService.new
  service.authorization = credentials

  query = "is:inbox"
  result = service.list_user_messages('me', q: query, max_results: 5, label_ids: ['IMPORTANT'])

  result.messages.each do |message|
    thread = service.get_user_thread("me", message.thread_id)
    
    has_draft = false
    thread.messages.each do |message|
      message = service.get_user_message("me", message.id)
      if message.label_ids.include?("DRAFT")
        has_draft = true
        break
      end
    end

    next if has_draft

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
  
  puts message.payload.inspect

  parts = message.payload.parts
  
  puts "No parts" && return if parts.nil? || parts.empty?

  text_part = parts.find { |part| part.mime_type == 'text/plain' }
  
  # Newsletters are `text/html` so we can skip them
  puts "No text/plain" && return if text_part.nil?

  email_content = text_part.body.data

  message = ::Mail.new
  message.to = [from, cc].flatten.compact.join(', ')
  message.subject = subject
  message.body = generate_email_response(email_content)
  message.content_type = 'text/plain; charset=UTF-8'
  encoded_message = Google::Apis::GmailV1::Message.new(raw: message.to_s, thread_id: thread_id)

  # Create the draft
  draft = Google::Apis::GmailV1::Draft.new(
    message: encoded_message
  )

  # Save the draft to Gmail
  service.create_user_draft('me', draft)
end

def generate_email_response(content)
  client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_KEY'), organization_id: ENV.fetch('OPENAI_ORG'))

  prompt = <<~MULTI_LINE_STRING
    I'm a venture capitalist. My tone is usually technical and doesn't use complicated sentences. I'm usually concise and stick to responding to the email without digressing too much.
    My investment interests are open source software, cybersecurity, developer tools, and software infrastructure, at Seed and Series A stage. 
    If a founder emails me a pitch that isn't in these areas of interest, I responding saying it's not a fit for us, and wish them good luck. If you don't have enough information to decide, don't say anything. 
    If the recipient asks to schedule, I respond asking to suggest times that work for them, or to pick one from my Calendly: https://calendly.com/alessio-decibel/catchup-call

    This is an email thread, it has both my emails (the ones from alessio@decibel.vc) and other people's:

    #{content}

    What should I respond? If you want to say something but don't know the details, add FILL_IN_HERE where you want me to edit it
  MULTI_LINE_STRING

  response = client.chat(
    parameters: {
        model: "gpt-4", # Required.
        messages: [{ role: "user", content: prompt}], # Required.
        temperature: 0.5,
    })

  puts response.inspect
  puts response['choices']
  response.dig("choices", 0, "message", "content").sub(/^\n*/, '')
end