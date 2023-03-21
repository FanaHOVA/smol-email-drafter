*All text and code is 99% GPT-4 generated*

To access your Gmail inbox using Ruby, you'll need to use the Google API Client library for Ruby and set up OAuth 2.0 authentication. Here's a step-by-step guide to help you achieve this:

Install the Google API Client library for Ruby:
Add these lines to your application's Gemfile:

```
source 'https://rubygems.org'

gem 'google-api-client'
gem 'sinatra'
```

Then run:

`bundle install`

### Create a new project on the Google API Console:

- Go to https://console.developers.google.com/ and sign in with your Google account.
- Click on "Create Project" and fill in the project name and organization.
- After creating the project, click on "Enable APIs and Services".
- In the API Library, search for "Gmail API" and enable it.

### Set up OAuth 2.0 credentials:
- In the Google API Console, go to the "Credentials" tab.
- Click "Create credentials" and choose "OAuth client ID".
- Select "Web application" as the application type.
- Set the authorized redirect URIs (e.g., "http://localhost:4567/oauth2callback" for a local development server).
- Click "Create" and note the generated client ID and client secret.
- Implement OAuth 2.0 in your Ruby application:
- Create a new Ruby file (e.g., gmail.rb) and insert the following code, replacing YOUR_CLIENT_ID and YOUR_CLIENT_SECRET with the values you obtained in step 3:

```
require 'sinatra'
require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'

OOB_URI = 'http://localhost:4567/oauth2callback'
CLIENT_ID = Google::Auth::ClientId.new('YOUR_CLIENT_ID', 'YOUR_CLIENT_SECRET')
TOKEN_STORE = Google::Auth::Stores::FileTokenStore.new(file: 'tokens.yaml')
AUTHORIZATION_URI = Google::Auth::WebUserAuthorizer::AUTHORIZATION_URI
AUTHORIZER = Google::Auth::WebUserAuthorizer.new(CLIENT_ID, [Google::Apis::GmailV1::AUTH_GMAIL_READONLY], TOKEN_STORE)

get '/' do
  if request['code']
    auth_code = request['code']
    credentials = AUTHORIZER.get_credentials_from_auth_code(auth_code, OOB_URI)
    list_emails(credentials)
  else
    redirect to(AUTHORIZER.get_authorization_url(login_hint: request['login_hint'], request: request))
  end
end

def list_emails(credentials)
  service = Google::Apis::GmailV1::GmailService.new
  service.authorization = credentials

  query = "is:unread"
  result = service.list_user_messages('me', q: query)

  emails = []
  result.messages.each do |message|
    msg = service.get_user_message('me', message.id)
    emails << msg
  end

  emails
end
```

This code sets up a simple Sinatra web application with an OAuth 2.0 flow. When you access the root path, the app redirects you to the Google OAuth consent screen. After granting access, you'll be redirected back to the app, which will list all unread emails in your inbox.

### Run the Ruby application:

`ruby gmail.rb`

### Access the app in your browser:

Navigate to http://localhost:4567 in your browser. You'll be redirected to the Google OAuth consent screen. After granting access, you should see a list of unread emails in your inbox.