require 'sinatra'
require 'erb'
require 'net-ldap'
require 'ruby-filemagic'
require 'rmagick'
require 'dotenv'

Dotenv.load

LDAP_HOST = ENV["LDAP_HOST"]
LDAP_BASE = ENV["LDAP_BASE"]
LDAP_DOMAIN = ENV["LDAP_DOMAIN"]
SUPPORT_EMAIL = ENV["SUPPORT_EMAIL"]

LDAP_PORT = ENV["LDAP_PORT"]
LDAP_ENCRYPTION = ENV["LDAP_ENCRYPTION"].intern

APP_PORT = ENV["APP_PORT"]
APP_MODE = ENV["APP_MODE"]
APP_SESSION_SECRET = ENV["APP_SESSION_SECRET"]

#pid management, requires the directory to be writable
File.open('server.pid', 'w') {|f| f.write Process.pid }

#files in public are served from "/"
PHOTO_FILE_PATH = "public/photos"

def validate_ldap_user(username, password)
  net_ldap_settings = {
    :host => LDAP_HOST,
    :base => LDAP_BASE,
    :port => LDAP_PORT,
    :encryption => LDAP_ENCRYPTION,
    :auth => {
      :method => :simple,
      :username => "#{username}@#{LDAP_DOMAIN}",
      :password => password
    }
  }
  
  ldap_connection = Net::LDAP.new(net_ldap_settings)

  search_parameter = username

  result_attributes = ["sAMAccountName"]
  
  search_filter = Net::LDAP::Filter.eq("sAMAccountName", search_parameter)
  
  ldap_connection.search(:filter => search_filter, :attributes => result_attributes)
  
  msg = "Response Code: #{ ldap_connection.get_operation_result.code }, Message: #{ ldap_connection.get_operation_result.message }"

  if ldap_connection.get_operation_result.code == 0
    return {:valid => true}
  else
    return {:valid => false, :errors => "Invalid username or password.  Please try again, or contact #{SUPPORT_EMAIL} for support.  System message: #{msg}"}
  end
end

def ldap_user_and_photo(username, password)
  
  net_ldap_settings = {
    :host => LDAP_HOST,
    :base => LDAP_BASE,
    :port => LDAP_PORT,
    :encryption => LDAP_ENCRYPTION,
    :auth => {
      :method => :simple,
      :username => "#{username}@#{LDAP_DOMAIN}",
      :password => password
    }
  }
  
  ldap_connection = Net::LDAP.new(net_ldap_settings)
  
  search_parameter = username

  result_attributes = ["sAMAccountName", "sn", "givenname", "thumbnailphoto"]
  
  search_filter = Net::LDAP::Filter.eq("sAMAccountName", search_parameter)
  
  users = ldap_connection.search(:filter => search_filter, :attributes => result_attributes)

  if ldap_connection.get_operation_result.code == 0
    user = users[0]
    return user
  else
    return nil
  end
end

def write_photo_to_filesystem(filename, photo_as_byte_string)
  
  File.open( "#{PHOTO_FILE_PATH}/#{filename}", 'wb' ) do |file|
    file.write(photo_as_byte_string)
  end
  
end

def update_photo(username, password, tmpfile_path)
  
  net_ldap_settings = {
    :host => LDAP_HOST,
    :base => LDAP_BASE,
    :port => LDAP_PORT,
    :encryption => LDAP_ENCRYPTION,
    :auth => {
      :method => :simple,
      :username => "#{username}@#{LDAP_DOMAIN}",
      :password => password
    }
  }
  
  ldap_connection = Net::LDAP.new(net_ldap_settings)
  
  search_parameter = username
  
  result_attributes = ["sAMAccountName", "thumbnailphoto"]
  
  search_filter = Net::LDAP::Filter.eq("sAMAccountName", search_parameter)
  
  users = ldap_connection.search(:filter => search_filter, :attributes => result_attributes)
  
  user = users[0]
  
  filetype = ""
  
  FileMagic.open(:mime) {|fm|
    filetype = fm.file(tmpfile_path) 
  }
  
  gif = "image/gif; charset=binary"
  jpeg = "image/jpeg; charset=binary"
  png = "image/png; charset=binary"
  
  if((filetype == gif) || (filetype == jpeg) || (filetype == png))
    
    width = 256
    height = 256
  
    img = Magick::Image.read(tmpfile_path).first().resize_to_fit!(width, height)

    target = Magick::Image.new(width, height) do
        self.background_color = 'white'
        self.format = 'JPEG'
    end

    target.composite(img, Magick::CenterGravity, Magick::CopyCompositeOp).write(tmpfile_path)
    
    octetstring = ""
  
    File.open(tmpfile_path) do |file|
      file.each do |line|
        octetstring << line
      end
    end
  
    ldap_connection.replace_attribute(user.dn, "thumbnailphoto", octetstring)
  
    msg = "Response Code: #{ ldap_connection.get_operation_result.code }, Message: #{ ldap_connection.get_operation_result.message }"
  
    if ldap_connection.get_operation_result.code == 0
      return {:valid => true, :user => user}
    else
      return {:valid => false, :errors => "LDAP update of photo data failed.  Please try again, or contact #{SUPPORT_EMAIL} for support.  System message: #{msg}"}
    end
  else
    return {:valid => false, :errors => "You did not upload a JPEG, PNG or GIF.  Please try again with a different image, or contact #{SUPPORT_EMAIL} for support.  System message: #{filetype}"}
  end
end


#####################################

enable :sessions
set :port, APP_PORT
set :environment, APP_MODE
#workaround for Chrome
use Rack::Session::Cookie, :secret => APP_SESSION_SECRET

helpers do
  def authorize!
    redirect(to('/login')) unless session[:valid]
  end
end

get '/' do
  redirect to('/login')
end

get '/login' do
  erb :login
end

post '/login' do
  user = validate_ldap_user(params[:username], params[:password])

  if (user[:valid])
    session[:username] = params[:username]
    session[:password] = params[:password]
    session[:valid] = true
    session[:flash] = ""

    redirect to('/upload')
  else
    session[:flash] = user[:errors]
    redirect to('/login')
  end
end

get '/upload' do
  authorize!
  
  #retrieve user via LDAP
  @user = ldap_user_and_photo(session[:username], session[:password])
  
  #check if they have a photo
  if(@user.attribute_names.include?(:thumbnailphoto))
    #write photo to disk
    photo_filename = "#{@user.samaccountname[0]}.jpg"
    write_photo_to_filesystem(photo_filename, @user.thumbnailphoto[0])
    erb :upload
  else
    erb :upload_no_photo
  end

end

post '/upload' do
  authorize!

  if (params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename]))
    #upload photo to LDAP
    result = update_photo(session[:username], session[:password], params[:file][:tempfile].path)
    
    if(result[:valid])
      #retrieve user via LDAP
      @user = ldap_user_and_photo(session[:username], session[:password])

      #write photo to disk
      photo_filename = "#{@user.samaccountname[0]}.jpg"
      write_photo_to_filesystem(photo_filename, @user.thumbnailphoto[0])

      #show new photo in the view
      erb :upload_result
    else
      session[:flash] = result[:errors]
      redirect to('/upload')
    end
  else
    session[:flash] = "error uploading file"
    redirect to('/upload')
  end
end

get '/logout' do  
  session.clear
  redirect to('/login')
end