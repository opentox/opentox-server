require_relative 'helper.rb'

module OpenTox

  # Base class for OpenTox services
  class Service < Sinatra::Base

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
      render $mongo[SERVICE].find.sort(:date).distinct(:uri)
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
