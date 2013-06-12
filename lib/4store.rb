module OpenTox
  module Backend
    class FourStore

      @@accept_formats = [ "application/rdf+xml", "text/turtle", "text/plain", "text/uri-list", "text/html", 'application/sparql-results+xml' ]
      @@content_type_formats = [ "application/rdf+xml", "text/turtle", "text/plain", "application/x-turtle" ]

      def self.list mime_type
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.join(", ")} in the Accept Header." unless @@accept_formats.include? mime_type
        if mime_type =~ /(uri-list|html|sparql-results)/
          sparql = "SELECT DISTINCT ?s WHERE {GRAPH ?g {?s <#{RDF.type}> <#{klass}>.} }"
        else
          sparql = "CONSTRUCT {?s <#{RDF.type}> <#{klass}>.} WHERE { GRAPH ?g {?s <#{RDF.type}> <#{klass}>.} }"
        end
        query sparql, mime_type
      end

      def self.head uri
        sparql = "SELECT DISTINCT ?g WHERE {GRAPH ?g {<#{uri}> ?p ?o.} }"
        rdf = query sparql, 'application/sparql-results+xml'
        resource_not_found_error "#{uri} not found." unless rdf.match("#{uri}")
        rdf
      end

      def self.get uri, mime_type
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.join(", ")} in the Accept Header." unless @@accept_formats.include? mime_type
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE { ?s ?p ?o. }"
        rdf = query sparql, mime_type
        resource_not_found_error "#{uri} not found." if rdf.empty?
        rdf
      end

      def self.post uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.join(", ")}." unless @@content_type_formats.include? mime_type or mime_type == "multipart/form-data"
        bad_request_error "Request body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain" # ntriples is turtle in 4store
        RestClient.post File.join(four_store_uri,"data")+"/", :data => rdf.gsub(/\\C/,'C'), :graph => uri, "mime-type" => mime_type # remove backslashes in SMILES (4store interprets them as UTF-8 \C even within single quoates)
        update "INSERT DATA { GRAPH <#{uri}> { <#{uri}> <#{RDF::DC.modified}> \"#{DateTime.now}\" } }"
      end

      def self.put uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.join(", ")}." unless @@content_type_formats.include? mime_type
        bad_request_error "Reqest body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain"
        RestClientWrapper.put File.join(four_store_uri,"data",uri), rdf, :content_type => mime_type
        update "INSERT DATA { GRAPH <#{uri}> { <#{uri}> <#{RDF::DC.modified}> \"#{DateTime.now}\" } }"
      end

      def self.delete uri
        RestClientWrapper.delete data_uri(uri)
      end

      def self.update sparql
        attempts = 0
        begin
          attempts += 1
          RestClient.post(update_uri, :update => sparql )
        rescue
          if attempts < 4 # 4store may return errors under heavy load
            sleep 1
            retry
          else
            bad_request_error $!.message, update_uri
          end
        end
      end

      def self.query sparql, mime_type
        if sparql =~ /SELECT/i
          # return list unless mime_type
          case mime_type
          when 'application/sparql-results+xml'
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body
          when 'application/json'
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body
          when /(uri-list|html)/
            uri_list = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body.gsub(/"|<|>/,'').split("\n").drop(1).join("\n")
            uri_list = uri_list.to_html if mime_type=~/html/
            return uri_list
          else
            bad_request_error "#{mime_type} is not a supported mime type for SELECT statements."
          end
        elsif sparql =~ /CONSTRUCT/i
          case mime_type
          when "text/plain", "application/rdf+xml" 
            RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body
          when /turtle/
            nt = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/tab-separated-values").body # 4store returns ntriples for turtle
            if !nt.empty?
              rdf = RDF::Graph.new
              RDF::Reader.for(:ntriples).new(nt) do |reader|
                reader.each_statement { |statement| rdf << statement }
              end
              prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"}
              ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
              # TODO: fails for large datasets?? multi_cell_call
              turtle = RDF::Turtle::Writer.for(:turtle).buffer(:prefixes => prefixes) do |writer|
                writer << rdf
              end
            else
              nt
            end
          when /html/
            # modified ntriples output, delivers large datasets
            #TODO optimize representation
            nt = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body
            if !nt.empty?
              regex = Regexp.new '(https?:\/\/[\S]+)([>"])'
              bnode = Regexp.new '_:[a-z0-9]*'
              html =  "<html><body>" + nt.gsub(regex, '<a href="\1">\1</a>\2').gsub(/\n/,'<br/>').gsub(bnode, '<>') + "</body></html>"
              html
            else
              nt
            end
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
