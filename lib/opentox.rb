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
      also_reload "./**/*.rb"
      also_reload "../opentox-client/lib/*.rb"
      also_reload File.join(ENV["HOME"],".opentox","config","#{SERVICE}.rb")
    end

    before do
      @uri = uri(request.env['PATH_INFO']) # prevent /algorithm/algorithm in algorithm service
      get_subjectid if respond_to? :get_subjectid
      # fix IE
      request.env['HTTP_ACCEPT'] += ";text/html" if request.env["HTTP_USER_AGENT"]=~/MSIE/
      request.env['HTTP_ACCEPT'] = request.params["media"] if request.params["media"]

      request.content_type ? response['Content-Type'] = request.content_type : response['Content-Type'] = request.env['HTTP_ACCEPT']
      parse_input if request.request_method =~ /POST|PUT/
      @accept = request.env['HTTP_ACCEPT']
      @accept = "text/html" if @accept =~ /\*\/\*/ or request.env["HTTP_USER_AGENT"]=~/MSIE/
      @accept = request.params["media"] if request.params["media"]
      Authorization.check_policy(@uri, @subjectid) if env['REQUEST_METHOD'] == "PUT" && $aa[:uri]
      response['Content-Type'] = @accept
    end

    after do
      Authorization.check_policy(@uri, @subjectid) if env['REQUEST_METHOD'].to_s == "POST" && $aa[:uri]

    end


    helpers do
      def parse_input
        case request.content_type 
        when /multipart/
          if params[:file]
            @body = params[:file][:tempfile].read
            # sdf files are incorrectly detected
            @content_type = params[:file][:type]
            @content_type = "chemical/x-mdl-sdfile" if File.extname(params[:file][:filename]) == ".sdf"
          end
        else
          @body = request.body.read
          @content_type = request.content_type
        end
      end

      # format output according to accept header
      def render object
        if object.class == String
          case @accept
          when /text\/html/
            content_type "text/html"
            object.to_html
          else
            content_type 'text/uri-list'
            object
          end
        elsif object.class == Array
          content_type 'text/uri-list'
          object.join "\n"
        else
          case @accept
          when "application/rdf+xml"
            content_type "application/rdf+xml"
            object.to_rdfxml
          when /text\/html/
            content_type "text/html"
            object.to_html
          when /turtle/
            content_type "text/turtle"
            object.to_turtle
          else
            content_type "text/plain"
            object.to_ntriples
          end
    
        end
      end
    end

    # Attention: Error within tasks are catched by Task.run
    error do
      error = request.env['sinatra.error']
      if error.respond_to? :report
        body = error.report.to_turtle
      else
        response['Content-Type'] = "text/plain"
        body = "#{error.message}\n"
        body += "URI: #{error.uri}\n" if error.is_a?(RuntimeError)
        body += error.backtrace.join("\n")
      end
      error.respond_to?(:http_code) ? code = error.http_code : code = 500
      halt code, body
    end
    
    def return_task( task )
      raise "http_code == nil" unless task.code!=nil
      case request.env['HTTP_ACCEPT']
      when /rdf/
        response['Content-Type'] = "application/rdf+xml"
        halt task.code,task.to_rdfxml
      when /yaml/
        response['Content-Type'] = "application/x-yaml"
        halt task.code,task.to_yaml # PENDING differs from task-webservice
      when /html/
        response['Content-Type'] = "text/html"
        # html -> task created with html form -> redirect to task uri
        redirect task.uri 
      else # default /uri-list/
        response['Content-Type'] = "text/uri-list"
        if task.completed?
          halt task.code,task.resultURI+"\n"
        else
          halt task.code,task.uri+"\n"
        end
      end
    end    

    # Default methods, may be overwritten by derived services
    # see http://jcalcote.wordpress.com/2008/10/16/put-or-post-the-rest-of-the-story/

    # HEAD route for service check
    # algorithm, compound and validation overwrite this
    head "/#{SERVICE}/?" do
    end

    # HEAD request for object in backend
    # algorithm, dataset, compound and validation overwrite this
    head "/#{SERVICE}/:id/?" do
      resource_not_found_error "#{uri} not found." unless FourStore.head(@uri.split('?').first)
    end

    # Get a list of objects at the server or perform a SPARQL query
    get "/#{SERVICE}/?" do
      if params[:query]
        case @accept
        when "text/uri-list" # result URIs are protected by A+A
          FourStore.query(params[:query], "text/uri-list") 
        else # prevent searches for protected resources
          bad_request_error "Accept header '#{@accept}' is disabled for SPARQL queries at service URIs in order to protect private data. Use 'text/uri-list' and repeat the query at the result URIs.", uri("/#{SERVICE}")
        end
      else
        FourStore.list(@accept)
      end
    end

    # Create a new resource
    post "/#{SERVICE}/?" do
      @uri = uri("/#{SERVICE}/#{SecureRandom.uuid}")
      FourStore.put(@uri, @body, @content_type)
      response['Content-Type'] = "text/uri-list"
      @uri
    end

    # Get resource representation or perform a SPARQL query
    get "/#{SERVICE}/:id/?" do
      params[:query] ?  FourStore.query(params[:query], @accept) : FourStore.get(@uri.split('?').first, @accept)
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
