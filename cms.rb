require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
end

before do
  @files = Dir["#{data_path}/*"].map do |path|
    File.basename(path)
  end.sort
end

def user_signed_in?
  session.key?(:username)
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def users_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test', __FILE__)
  else
    File.expand_path('..', __FILE__)
  end
end

def signup_error_message
  case @error_type
  when :empty_field
    "No field can be empty"
  when :includes_spaces
    "Username/password cannot include spaces"
  when :password_mismatch
    "Passwords did not match"
  when :not_unique
    "Username must be unique"
  end
end

def any_fields_empty?(*fields)
  fields.any? { |field| field.empty? }
end

def fields_include_spaces?(*fields)
  fields.any? { |field| field.include?(' ') }
end

def invalid_signup?(username, password, confirmation)
  users = load_user_credentials
  !!@error_type = (if any_fields_empty?(username, password, confirmation)
                     :empty_field
                   elsif password != confirmation
                     :password_mismatch
                   elsif fields_include_spaces?(username, password)
                     :includes_spaces
                   elsif users.keys.include?(username)
                     :not_unique
                   end)
end

def load_file_content(path)
  extension = File.extname(path)
  content = File.read(path)
  case extension
  when '.md'
    erb render_markdown(content)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  end
end

def get_data_path(file)
  File.join(data_path, file)
end

def get_users_path(file)
  File.join(users_path, file)
end

def load_user_credentials
  if ENV['RACK_ENV'] == 'test'
    path = File.expand_path('../test/users.yml', __FILE__)
  else
    path = File.expand_path('../users.yml', __FILE__)
  end
  YAML.load_file(path)
end

def update_users(username, password)
  new_user = {username => BCrypt::Password.create(password)}
  path = get_users_path('users.yml')
  File.open(path, 'a+') do |users|
    users.write(new_user.to_yaml.gsub("---", ''))
  end
end

def invalid_file_name?(file_name)
  extension = File.extname(file_name)
  !!@error_type = (if file_name.size == 0
                     :empty_name
                   elsif file_name.include?(' ')
                     :includes_spaces
                   elsif File.extname(file_name).empty?
                     :no_extension
                   elsif @files.include?(file_name)
                     :not_unique
                   elsif %w(.md .txt).none? { |type| type == extension }
                     :wrong_type
                   end)
end

def file_error_message
  case @error_type
  when :empty_name
    "A name is required"
  when :no_extension
    "File name must have an extension"
  when :includes_spaces
    "File name cannot include spaces"
  when :not_unique
    "File names must be unique"
  when :wrong_type
    "That file type is not supported"
  end
end

def require_signed_in_user
  unless user_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect '/'
  end
end

helpers do
  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, strikethrough: true)
    markdown.render(text)
  end
end

get '/' do
  erb :index
end

get '/users/signin' do
  erb :sign_in
end

get %r(\A\/(\w+\.\w+)\z) do |file|
  path = get_data_path(file)
  if File.exist?(path)
    load_file_content(path)
  else
    session[:message] = "#{file} does not exist"
    redirect '/'
  end
end

get %r(\A\/(\w+\.\w+)\/edit\z) do |file|
  require_signed_in_user
  path = get_data_path(file)
  if File.exist?(path)
    @file_name = file
    @contents = File.read(path)
    erb :edit
  else
    session[:message] = "#{file} does not exist"
    redirect '/'
  end
end

post %r(\A\/(\w+\.\w+)\z) do |file|
  require_signed_in_user
  path = get_data_path(file)
  File.write(path, params[:content])
  session[:message] = "#{file} has been updated."
  redirect '/'
end

get '/new' do
  require_signed_in_user
  erb :new
end

post '/create' do
  require_signed_in_user
  file_name = params[:file_name].strip
  if invalid_file_name?(file_name)
    session[:message] = file_error_message
    status 422
    erb :new
  else
    path = get_data_path(file_name)
    File.write(path, '')
    session[:message] = "#{file_name} has been created."
    redirect '/'
  end
end

post %r(\A\/(\w+\.\w+)\/delete\z) do |file|
  require_signed_in_user
  File.delete(get_data_path(file))
  session[:message] = "#{file} has been deleted."
  redirect '/'
end

post "/users/signin" do
  users = load_user_credentials
  if users[params[:username]] == params[:password]
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect '/'
  else
    status 422
    session[:message] = "Invalid credentials"
    erb :sign_in
  end
end

post "/users/signout" do
  session[:message] = "You have been signed out"
  session.delete(:username)
  redirect '/'
end

get %r(\A\/(\w+\.\w+)\/copy\z) do |file|
  @file = file
  require_signed_in_user
  erb :copy
end

post %r(\A\/(\w+\.\w+)\/copy\z) do |file|
  @file = file
  file_name = params[:file_name]
  if invalid_file_name?(file_name)
    session[:message] = file_error_message
    status 422
    erb :copy
  else
    old_path = get_data_path(file)
    contents_to_copy = File.read(old_path)
    path = get_data_path(file_name)
    File.write(path, contents_to_copy)
    session[:message] = "Contents of #{file} copied to #{file_name}."
    redirect '/'
  end
end

get '/users/signup' do
  erb :signup
end

post '/users/signup' do
  username = params[:username]
  password = params[:password]
  confirmation = params[:confirmation]
  unless invalid_signup?(username, password, confirmation)
    session[:message] = "#{username} added as user"
    update_users(username, password)
    redirect '/'
  else
    session[:message] = signup_error_message
    status 422
    erb :signup
  end
end