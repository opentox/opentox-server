require 'sinatra/base'
require "sinatra/reloader"

module OpenTox

  # Base class for OpenTox services
  class Service < Sinatra::Base

    helpers Sinatra::UrlForHelper
    # use OpenTox error handling
    set :raise_errors, false
    set :show_exceptions, false
    set :static, false

    configure :development do
      register Sinatra::Reloader
    end

    helpers do
      def uri
        params[:id] ? url_for("/#{params[:id]}", :full) : "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
      end
    end

    before do
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
      # TODO: A+A
    end

    error do
      # TODO: convert to OpenTox::Error and set URI
      error = request.env['sinatra.error']
      #error.uri = uri
      if error.respond_to? :report
        # Errors are formated according to acccept-header
        case @accept
        when 'application/rdf+xml'
          body = error.report.to_rdfxml
        when /html/
          # TODO
          # body = error.report.to_html
          body = error.report.to_turtle
        when "text/n3"
          body = error.report.to_ntriples
        else
          body = error.report.to_turtle
        end
      else
        response['Content-Type'] = "text/plain"
        body = error.message
        body += "\n#{error.backtrace}"
      end
      error.respond_to?(:http_code) ? code = error.http_code : code = 500
      halt code, body
    end
  end
end

