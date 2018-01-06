ENV['RACK_ENV'] = 'test'

require 'rack/test'
require 'minitest/autorun'
require 'minitest/reporters'
require 'fileutils'

require_relative '../cms'

Minitest::Reporters.use!

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session
    last_request.env['rack.session']
  end

  def admin_session
    {'rack.session' => {username: 'admin', password: 'secret'}}
  end

  def create_document(name, content="")
    path = get_data_path(name)
    File.open(get_data_path(name), 'w') do |file|
      file.write(content)
    end
  end

  def setup
    FileUtils.mkdir_p(data_path)

    FileUtils.touch(get_users_path('users.yml'))

    update_users('admin', 'secret')
  end

  def teardown
    FileUtils.rm_rf(data_path)

    FileUtils.rm(get_users_path('users.yml'))
  end

  def test_index
    create_document('about.md')
    create_document('changes.txt')

    get '/'

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'changes.txt'
    assert_includes last_response.body, 'New Document'
  end

  def test_viewing_text_document
    create_document('history.txt', "Ruby 0.95 released")

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_nonexistent_doc
    get "/unknown.ext"

    assert_equal 302, last_response.status
    assert_equal "unknown.ext does not exist", session[:message]
  end

  def test_markdown
    create_document('about.md', '*dynamic*')

    get "/about.md"
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, '<em>dynamic</em>'
  end

    def test_editing_document
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type='submit')
  end

  def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt", {content: "new content"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type='submit')
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document
    post "/create", {file_name: "test.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been created.", session[:message]

    get "/"
    assert_includes last_response.body, "test.txt"
  end

  def test_create_new_document_signed_out
    post "/create", {file_name: "test.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document_without_file_name
    post "/create", {file_name: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required"
  end

  def test_deleting_document
    create_document("test.txt")

    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_deleting_document_signed_out
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type='submit')
  end

  def test_signin
    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response['Location']
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin",username: "guest", password: "shhhh"
    assert_equal 422, last_response.status
    assert_equal nil, session[:username]
    assert_includes last_response.body, "Invalid credentials"
  end

  def test_signout
    get '/', {}, admin_session
    assert_includes last_response.body, 'Signed in as admin'

    post "/users/signout"
    get last_response['Location']

    assert_includes last_response.body, "You have been signed out"
    assert_includes last_response.body, 'Sign In'
  end

  def test_signup
    post '/users/signup', username: 'grant', password: 'password', confirmation: 'password'

    assert_equal "grant added as user", session[:message]
  end

  def test_invalid_signup
    post '/users/signup', username: 'grant', password: 'password', confirmation: ''

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'No field can be empty'
  end
end