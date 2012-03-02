require 'sinatra/base'
# Error handling
# Errors are logged as error and formated according to acccept-header
# Non OpenTox::Errors (defined in error.rb) are handled as internal error (500), stacktrace is logged
# IMPT: set sinatra settings :show_exceptions + :raise_errors to false in config.ru, otherwise Rack::Showexceptions takes over

module OpenTox
  class Service < Sinatra::Base
    helpers Sinatra::UrlForHelper
    set :raise_errors, false
    set :show_exceptions, false
    error do
      #TODO: add actor to error report
      #actor = "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}"
      error = request.env['sinatra.error']
      case request.env['HTTP_ACCEPT']
      when 'application/rdf+xml'
        content_type 'application/rdf+xml'
      when /html/
        content_type 'text/html'
      when "text/n3"
        content_type "text/n3"
      else
        content_type "text/n3"
      end
      if error.respond_to? :report
        code = error.report.http_code
        case request.env['HTTP_ACCEPT']
        when 'application/rdf+xml'
          body = error.report.to_rdfxml
        when /html/
          body = error.report.to_yaml
        when "text/n3"
          body = error.report.to_ntriples
        else
          body = error.report.to_ntriples
        end
      else
        content_type "text/plain"
        body = error.message
        body += "\n#{error.backtrace}"
      end

      halt code, body
    end
  end
end

