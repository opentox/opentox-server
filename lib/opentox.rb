require 'sinatra/base'
require "sinatra/reloader"
require 'mongo'

ENV["RACK_ENV"] ||= "production"
require File.join(ENV["HOME"],".opentox","config","default.rb") if File.exist? File.join(ENV["HOME"],".opentox","config","default.rb")
require File.join(ENV["HOME"],".opentox","config","#{SERVICE}.rb")
$aa[SERVICE.to_sym] = $aa

logfile = File.join(ENV['HOME'], ".opentox","log","#{ENV["RACK_ENV"]}.log")
$logger = OTLogger.new(logfile)

Mongo::Logger.logger = $logger
Mongo::Logger.logger.level = Logger::WARN 
$mongo = Mongo::Client.new($mongodb[:uri])
#$mongo[SERVICE].create if $mongo[SERVICE].find.count == 0
# TODO create collections $mongo[SERVICE].create if $mongo[SERVICE].find.count == 0

module OpenTox

  # Base class for OpenTox services
  class Service < Sinatra::Base

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
      @uuid = params[:id]
      get_subjectid if respond_to? :get_subjectid
      # fix for IE, and set accept to 'text/html' as we do exact-matching later (sth. like text/html,application/xhtml+xml,*/* is not supported)
      request.env['HTTP_ACCEPT'] = "text/html" if request.env["HTTP_USER_AGENT"]=~/MSIE/ or request.env['HTTP_ACCEPT']=~/text\/html/
      # support set accept via url by adding ?media=<type> to the url
      request.env['HTTP_ACCEPT'] = request.params["media"] if request.params["media"]
      # default is turtle ??
      #request.env['HTTP_ACCEPT'] = "text/turtle" if request.env['HTTP_ACCEPT'].size==0 or request.env['HTTP_ACCEPT']=~/\*\/\*/
      # default is application/json
      request.env['HTTP_ACCEPT'] = "application/json" if request.env['HTTP_ACCEPT'].size==0 or request.env['HTTP_ACCEPT']=~/\*\/\*/
      @accept = request.env['HTTP_ACCEPT']

      request.content_type ? response['Content-Type'] = request.content_type : response['Content-Type'] = request.env['HTTP_ACCEPT']
      parse_input if request.request_method =~ /POST|PUT/
      Authorization.check_policy(@uri) if env['REQUEST_METHOD'] == "PUT" && $aa[SERVICE.to_sym][:uri] && $aa[SERVICE.to_sym]
      response['Content-Type'] = @accept
    end

    after do
      Authorization.check_policy(@uri) if env['REQUEST_METHOD'].to_s == "POST" && $aa[SERVICE.to_sym][:uri] && $aa[SERVICE.to_sym]
      Authorization.delete_policies_from_uri(@uri) if env['REQUEST_METHOD'].to_s == "DELETE" && $aa[SERVICE.to_sym][:uri] && $aa[SERVICE.to_sym]
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
        content_type @accept
        return nil if object.nil?
        if @accept == "application/json"
          #object.delete("_id") if object and object["_id"]
          return object.to_json
        else
          if object.class == String
            case @accept
            when /text\/html/
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
              object.to_rdfxml
            when /text\/html/
              object.to_html
            when /turtle/
              object.to_turtle
            when 'text/plain'
              object.to_ntriples
            else
              bad_request_error "Mime type '#{@accept}' is not supported."
            end

          end
        end
      end
    end


    # ERROR HANDLING (for errors outside of tasks, errors inside of tasks are taken care of in Task.run)
    def return_ot_error(ot_error)
      case @accept
      when /text\/html/
        content_type "text/html"
        halt ot_error.http_code, ot_error.to_html
      else
        content_type "application/json"
        halt ot_error.http_code, ot_error.to_json
      end
    end

    error Exception do # wraps non-opentox-errors like NoMethodError within an InternalServerError
      error = request.env['sinatra.error']
      return_ot_error(OpenTox::Error.new(500,error.message,nil,error.backtrace))
    end

    error OpenTox::Error do # this covers all opentox errors
      return_ot_error(request.env['sinatra.error'])
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

    # HEAD methods only used if there is no GET method in the particular service
    # E.g. "head "/#{SERVICE}/:id/?"" is overwritten by "get '/task/:id/?'"
	  # The following HEAD methods are only used by the feature service

    # HEAD route for service check
    # algorithm, dataset, model, compound, and validation overwrite this
    head "/#{SERVICE}/?" do
    end

    # HEAD request for object in backend
    # algorithm, dataset, model, compound, and validation overwrite this
    head "/#{SERVICE}/:id/?" do
      halt 404 unless $mongo[SERVICE].find(:uri => @uri).count > 0
    end

    get "/#{SERVICE}/swagger" do
    end

    # Get a list of objects at the server or perform a SPARQL query
    get "/#{SERVICE}/?" do
      if params[:query]
        case @accept
        when "text/uri-list" # result URIs are protected by A+A
          render $mongo[SERVICE].find(params[:query]).distinct(:uri)
        else # prevent searches for protected resources
          bad_request_error "Accept header '#{@accept}' is disabled for SPARQL queries at service URIs in order to protect private data. Use 'text/uri-list' and repeat the query at the result URIs.", uri("/#{SERVICE}")
        end
      else
        render $mongo[SERVICE].find.distinct(:uri)
      end
    end

    # internal route not in API
    get "/#{SERVICE}/last/ordered/?" do # REQUIRED?
      FourStore.query("SELECT DISTINCT ?s WHERE
      {GRAPH ?g
        {?s <#{RDF.type}> <#{RDF::OT}#{SERVICE.capitalize}>; <#{RDF::DC.date}> ?o. }
      } ORDER BY ?o ", @accept)
    end

    # Create a new resource
    post "/#{SERVICE}/?" do
      @body[:uuid] = SecureRandom.uuid
      @body[:uri] = uri("/#{SERVICE}/#{@body[uuid]}")
      $mongo[SERVICE].insert_one @body
      response['Content-Type'] = "text/uri-list"
      @uri
    end

    # Get resource representation 
    get "/#{SERVICE}/:id/?" do 
      response = $mongo[SERVICE].find(:uri => @uri)
      response.count > 0 ? render(response.first) : resource_not_found_error("#{@uri} not found.")
    end

    # Modify (i.e. add rdf statments to) a resource
    post "/#{SERVICE}/:id/?" do 
      $mongo[SERVICE].find(:uri => @uri).find_one_and_replace('$set' => JSON.parse(@body))
      @uri
    end

    # Create or updata a resource
    put "/#{SERVICE}/:id/?" do
      @body = JSON.parse(@body)
      @body.delete("_id") # to enable updates
      @body[:uri] = @uri
      render $mongo[SERVICE].find(:uri => @uri).find_one_and_replace(@body, :upsert => true)
    end

    # Delete a resource
    delete "/#{SERVICE}/:id/?" do
      render $mongo[SERVICE].find(:uri => @uri).find_one_and_delete
    end

  end
end
