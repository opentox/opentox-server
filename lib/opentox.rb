require 'sinatra/base'
require "sinatra/reloader" 
ENV["RACK_ENV"] ||= "production"
require File.join(ENV["HOME"],".opentox","config","default.rb") if File.exist? File.join(ENV["HOME"],".opentox","config","default.rb")
require File.join(ENV["HOME"],".opentox","config","#{SERVICE}.rb")


logfile = File.join(ENV['HOME'], ".opentox","log","#{ENV["RACK_ENV"]}.log")
$logger = OTLogger.new(logfile) 

module OpenTox

  # Base class for OpenTox services
  class Service < Sinatra::Base
    include Backend

    # use OpenTox error handling
    set :raise_errors, false
    set :show_exceptions, false
    set :static, false

    configure :development do
      register Sinatra::Reloader
      also_reload "./*.rb"
      also_reload "../opentox-client/lib/*.rb"
      also_reload File.join(ENV["HOME"],".opentox","config","#{SERVICE}.rb")
    end

    before do
      request.content_type ? response['Content-Type'] = request.content_type : response['Content-Type'] = request.env['HTTP_ACCEPT']
      parse_input if request.request_method =~ /POST|PUT/
      @accept = request.env['HTTP_ACCEPT']
    end

    before "/#{SERVICE}/:id" do
      @uri = uri("/#{SERVICE}/#{params[:id]}")
    end

    helpers do
      def parse_input
        case request.content_type 
        when /multipart/
          @body = params[:file][:tempfile].read
          # sdf files are incorrectly detected
          @content_type = params[:file][:type]
          @content_type = "chemical/x-mdl-sdfile" if File.extname(params[:file][:filename]) == ".sdf"
        else
          @body = request.body.read
          @content_type = request.content_type
        end
      end
    end

    # Attention: Error within tasks are catched by Task.create
    error do
      error = request.env['sinatra.error']
      if error.respond_to? :report
        body = error.report.to_turtle
      else
        response['Content-Type'] = "text/plain"
        body = error.message
        body += "\n#{error.backtrace}"
      end
      error.respond_to?(:http_code) ? code = error.http_code : code = 500
      halt code, body
    end

    # Default methods, may be overwritten by derived services
    # see http://jcalcote.wordpress.com/2008/10/16/put-or-post-the-rest-of-the-story/

    # Get a list of objects at the server
    get "/#{SERVICE}/?" do
      FourStore.list uri("/#{SERVICE}"), @accept
    end

    # Create a new resource
    post "/#{SERVICE}/?" do
      @uri = uri("/#{SERVICE}/#{SecureRandom.uuid}")
      FourStore.put(@uri, @body, @content_type)
      response['Content-Type'] = "text/uri-list"
      @uri
    end

    # Get resource representation
    get "/#{SERVICE}/:id/?" do
      FourStore.get(@uri, @accept)
    end

    # Modify (i.e. add rdf statments to) a resource
    post "/#{SERVICE}/:id/?" do
      FourStore.post @uri, @body, @content_type
    end

    # Create or updata a resource
    put "/#{SERVICE}/:id/?" do
      FourStore.put @uri, @body, @content_type
    end

    # Delete a resource
    delete "/#{SERVICE}/:id/?" do
      FourStore.delete @uri
    end

  end
end
