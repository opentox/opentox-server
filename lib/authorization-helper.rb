module OpenTox
  # Base class for OpenTox services
  class Application < Service

    helpers do

      # Login to get session for browser application(e.G.: ToxCreate)
      #
      # @param [String, String] username,password
      # @return [String] subjectid from session or nil
      def login(username, password)
        logout
        session[:subjectid] = OpenTox::Authorization.authenticate(username, password)
        $logger.debug "ToxCreate login user #{username} with subjectid: " + session[:subjectid].to_s
        if session[:subjectid] != nil
          session[:username] = username
          return session[:subjectid]
        else
          session[:username] = ""
          return nil
        end
      end

      # Logout to reset session
      #
      # @return [Boolean] true/false
      def logout
        if session[:subjectid] != nil
          session[:subjectid] = nil
          session[:username] = ""
          return true
        end
        return false
      end

      # Checks session and valid subjectid token.
      # @return [Boolean] true/false
      def logged_in()
        return true if !$aa[:uri]
        if session[:subjectid] != nil
          return OpenTox::Authorization.is_token_valid(session[:subjectid])
        end
        return false
      end

      # Authorization for a browser/webservice request
      # webapplication: redirects with flash[:notice] if unauthorized
      # webservice: raises error  if unauthorized
      # @param [String]subjectid
      def protected!(subjectid)
        if env["session"]
          unless authorized?(subjectid)
            flash[:notice] = "You don't have access to this section: "
            redirect back
          end
        elsif !env["session"] && subjectid
          unless authorized?(subjectid)
            $logger.debug "URI not authorized: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").sub("http://","https://").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
            unauthorized_error "Not authorized #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
          end
        else
          unauthorized_error "Not authorized" unless authorized?(subjectid)
        end
      end

      # Check Authorization for URI with method and subjectid.
      # @param [String]subjectid
      def authorized?(subjectid)
        request_method = request.env['REQUEST_METHOD']
        uri = clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}") #.sub("http://","https://")
        request_method = "GET" if request_method == "POST" &&  uri =~ /\/model\/\d+\/?$/
        return OpenTox::Authorization.authorized?(uri, request_method, subjectid)
      end

      # Cleans URI from querystring and file-extension. Sets port 80 to emptystring
      # @param [String] uri
      def clean_uri(uri)
        uri = uri.sub(" ", "%20")          #dirty hacks => to fix
        uri = uri[0,uri.index("InChI=")] if uri.index("InChI=")
        out = URI.parse(uri)
        out.path = out.path[0, out.path.length - (out.path.reverse.rindex(/\/{1}\d+\/{1}/))] if out.path.index(/\/{1}\d+\/{1}/)  #cuts after numeric /id/ for a&a
        out.path.sub! /(\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}).*/, '\1' # cut after uuid
        out.path = out.path.split('.').first #cut extension
        port = (out.scheme=="http" && out.port==80)||(out.scheme=="https" && out.port==443) ? "" : ":#{out.port.to_s}"
        "#{out.scheme}://#{out.host}#{port}#{out.path.chomp("/")}" #"
      end

      # Unprotected uri for login
      def login_request?
        return env['REQUEST_URI'] =~ /\/login$/
       end

      # Check if URI returns code 200 //used in model/lazar.rb
      # @param [String]URLString
      # @return [Boolean] true/false
      def uri_available?(urlStr)
        url = URI.parse(urlStr)
        subjectidstr = @subjectid ? "?subjectid=#{CGI.escape @subjectid}" : ""
        http = Net::HTTP.new(url.host, url.port)
        if url.is_a?(URI::HTTPS)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        return http.head("#{url.request_uri}#{subjectidstr}").code == "200"
      end

      # Get subjectid out of session, params or rack-environment and unescape it if necessary
      # @return [String] subjectid
      def get_subjectid
        #begin
          subjectid = nil
          subjectid = session[:subjectid] if session[:subjectid]
          subjectid = params[:subjectid]  if params[:subjectid] and !subjectid
          subjectid = request.env['HTTP_SUBJECTID'] if request.env['HTTP_SUBJECTID'] and !subjectid
          # see http://rack.rubyforge.org/doc/SPEC.html
          subjectid = CGI.unescape(subjectid) if subjectid.include?("%23")
          @subjectid = subjectid
        #rescue
        #  @subjectid = nil
        #end
      end

    end

    before do
      get_subjectid()
      unless !$aa[:uri] or login_request? or $aa[:free_request].include?(env['REQUEST_METHOD'].to_sym)
        protected!(@subjectid)
      end
    end
  end
end
