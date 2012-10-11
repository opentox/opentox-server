module OpenTox
  module Backend
    class FourStore

      @@accept_formats = [ "application/rdf+xml", "text/turtle", "text/plain", "text/uri-list", "text/html", 'application/sparql-results+xml' ]
      @@content_type_formats = [ "application/rdf+xml", "text/turtle", "text/plain" ]

      def self.list mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.join(", ")} in the Accept Header." unless @@accept_formats.include? mime_type
        if mime_type =~ /uri-list/
          sparql = "SELECT DISTINCT ?g WHERE {GRAPH ?g {?s <#{RDF.type}> <#{klass}>; ?p ?o. } }"
        else 
          sparql = "CONSTRUCT {?s ?p ?o.} WHERE {?s <#{RDF.type}> <#{klass}>; ?p ?o. }"
        end
        query sparql, mime_type
      end

      def self.get uri, mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.join(", ")} in the Accept Header." unless @@accept_formats.include? mime_type
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE { ?s ?p ?o. }"
        rdf = query sparql, mime_type
        resource_not_found_error "#{uri} not found." if rdf.empty?
        rdf
      end

      def self.post uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.join(", ")}." unless @@content_type_formats.include? mime_type or mime_type == "multipart/form-data"
        bad_request_error "Reqest body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain" # ntriples is turtle in 4store
        begin
          RestClient.post File.join(four_store_uri,"data")+"/", :data => rdf, :graph => uri, "mime-type" => mime_type 
        rescue
          bad_request_error $!.message, File.join(four_store_uri,"data")+"/"
        end
      end

      def self.put uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.join(", ")}." unless @@content_type_formats.include? mime_type
        bad_request_error "Reqest body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain"
        #begin
          RestClientWrapper.put File.join(four_store_uri,"data",uri), rdf, :content_type => mime_type 
        #rescue
          #bad_request_error $!.message, File.join(four_store_uri,"data",uri)
        #end
      end

      def self.delete uri
        RestClientWrapper.delete data_uri(uri)
      end

      def self.update sparql
        RestClient.post(update_uri, :update => sparql )
      end

      def self.query sparql, mime_type
        if sparql =~ /SELECT/i
#         return list unless mime_type
          case mime_type
          when 'application/sparql-results+xml' 
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body
          when "text/uri-list"
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body.gsub(/"|<|>/,'').split("\n").drop(1).join("\n")
          else
            bad_request_error "#{mime_type} is not a supported mime type for SELECT statements."
          end
        elsif sparql =~ /CONSTRUCT/i
          case mime_type
          when "text/plain", "application/rdf+xml" 
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body
          when /html|turtle/
            # TODO: fix and improve
            nt = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body # 4store returns ntriples for turtle

            rdf = RDF::Graph.new
            RDF::Reader.for(:ntriples).new(nt) do |reader|
              reader.each_statement { |statement| rdf << statement }
            end
            prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"}
            ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
            # TODO: fails for large datasets?? multi_cell_call
            turtle = RDF::N3::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
              rdf.each{|statement| writer << statement}
            end
            regex = Regexp.new '(https?:\/\/[\S]+)([>"])'
            turtle =  "<html><body>" + turtle.gsub( regex, '<a href="\1">\1</a>\2' ).gsub(/\n/,'<br/>') + "</body></html>" if mime_type =~ /html/ and !turtle.empty?
            turtle
          end
        else
          # TODO: check if this prevents SPARQL injections
          bad_request_error "Only SELECT and CONSTRUCT are accepted SPARQL statements."
        end
      rescue
        bad_request_error $!.message, sparql_uri
      end

      def self.klass
        RDF::OT[SERVICE.capitalize]
      end

      def self.four_store_uri
        # credentials are removed from uri in error.rb
        $four_store[:uri].sub(%r{//},"//#{$four_store[:user]}:#{$four_store[:password]}@")
      end

      def self.sparql_uri 
        File.join(four_store_uri, "sparql") + '/'
      end

      def self.update_uri 
        File.join(four_store_uri, "update") + '/'
      end

      def self.data_uri uri
        File.join(four_store_uri, "data","?graph=#{uri}")
      end

    end
  end
end
