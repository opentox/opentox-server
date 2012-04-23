require 'sinatra/base'
require "sinatra/reloader"
require File.join(ENV["HOME"],".opentox","config","default.rb")

ENV["RACK_ENV"] ||= "production"

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
    end

    before do
      request.content_type ? response['Content-Type'] = request.content_type : response['Content-Type'] = request.env['HTTP_ACCEPT']
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
    get '/?' do
      FourStore.list request.env['HTTP_ACCEPT']
    end

    # Create a new URI, does not accept a payload (use put for this purpose)
    post '/?' do
      uri = uri(SecureRandom.uuid)
      FourStore.put uri, request.body.read, request.content_type
      response['Content-Type'] = "text/uri-list"
      uri
    end

    # Get resource representation
    get '/:id/?' do
      FourStore.get(uri("/#{params[:id]}"), request.env['HTTP_ACCEPT'])
    end

    # Modify (add rdf) a resource
    post '/:id/?' do
      FourStore.post uri("/#{params[:id]}"), request.body.read, request.content_type
    end

    # Create or updata a resource
    put '/:id/?' do
      FourStore.put uri("/#{params[:id]}"), request.body.read, request.content_type
    end

    # Delete a resource
    delete '/:id/?' do
      FourStore.delete uri("/#{params[:id]}")
    end

  end
end
