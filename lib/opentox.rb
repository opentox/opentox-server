require 'sinatra/base'
ENV["RACK_ENV"] ||= "production"
require "sinatra/reloader" if ENV["RACK_ENV"] == "development"
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
    set :prefix, SERVICE

    configure :development do
      register Sinatra::Reloader
    end

    before do
      request.content_type ? response['Content-Type'] = request.content_type : response['Content-Type'] = request.env['HTTP_ACCEPT']
      @prefix = "task"
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
    get "/#{settings.prefix}/?" do
      FourStore.list request.env['HTTP_ACCEPT']
    end

    # Create a new resource
    # TODO: handle multipart uploads
    post "/#{settings.prefix}/?" do
      rdf = request.body.read
      uri = uri("/#{settings.prefix}/#{SecureRandom.uuid}")
      FourStore.put(uri, rdf, request.content_type) unless rdf == ''
      response['Content-Type'] = "text/uri-list"
      uri
    end

    # Get resource representation
    get "/#{settings.prefix}/id/?" do
      FourStore.get(uri("/#{settings.prefix}/#{params[:id]}"), request.env['HTTP_ACCEPT'])
    end

    # Modify (i.e. add rdf statments to) a resource
    post "/#{settings.prefix}/:id/?" do
      FourStore.post uri("/#{settings.prefix}/#{params[:id]}"), request.body.read, request.content_type
    end

    # Create or updata a resource
    put "/#{settings.prefix}/:id/?" do
      FourStore.put uri("/#{settings.prefix}/#{params[:id]}"), request.body.read, request.content_type
    end

    # Delete a resource
    delete "/#{settings.prefix}/:id/?" do
      FourStore.delete uri("/#{settings.prefix}/#{params[:id]}")
    end

  end
end
