require 'sinatra/base'
require "sinatra/reloader"

module OpenTox
  # Base class for OpenTox services
  # Errors are formated according to acccept-header
  # Non OpenTox::Errors (defined in error.rb) are handled as internal error (500), stacktrace is logged
  class Service < Sinatra::Base

    helpers Sinatra::UrlForHelper
    # use OpenTox error handling
    set :raise_errors, false
    set :show_exceptions, false
    set :static, false

    configure :development do
      register Sinatra::Reloader
    end

    error do
      error = request.env['sinatra.error']
      error.uri = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}"
      case request.env['HTTP_ACCEPT']
      when 'application/rdf+xml'
        content_type 'application/rdf+xml'
      when /html/
        content_type 'text/html'
      when "text/n3"
        content_type "text/n3"
      else
        content_type "text/turtle"
      end
      if error.respond_to? :report
        case request.env['HTTP_ACCEPT']
        when 'application/rdf+xml'
          body = error.report.to_rdfxml
        when /html/
          body = error.report.to_yaml
        when "text/n3"
          body = error.report.to_ntriples
        else
          body = error.report.to_turtle
        end
      else
        content_type "text/plain"
        body = error.message
        body += "\n#{error.backtrace}"
      end
      error.respond_to?(:http_code) ? code = error.http_code : code = 500
      halt code, body
    end
  end
end

