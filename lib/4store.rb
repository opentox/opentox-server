module OpenTox
  module Backend
    class FourStore

      @@mime_format = {
        "application/rdf+xml" => :rdfxml,
        "text/turtle" => :turtle,
        "text/plain" => :ntriples,
        "text/uri-list" => :uri_list,
        #"application/json" => :json,
        #"application/x-yaml" => :yaml,
        #"text/x-yaml" => :yaml,
        #"text/yaml" => :yaml,
        "text/html" => :html,
        #/sparql/ => :sparql #removed to prevent sparql injections
        'application/sparql-results+xml' => :sparql
      }

      @@format_mime = {
        :rdfxml => "application/rdf+xml", 
        :turtle => "text/turtle",
        :ntriples => "text/plain",
        :uri_list => "text/uri-list",
        #:json => "application/json",
        #:yaml => "text/yaml",
        :html => "text/html",
        :sparql => 'application/sparql-results+xml'
      }

      @@accept_formats = [:rdfxml, :turtle, :ntriples, :uri_list, :html, :sparql] #, :json, :yaml]
      @@content_type_formats = [:rdfxml, :turtle, :ntriples]#, :json, :yaml]

      def self.list mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.collect{|f| @@format_mime[f]}.join(", ")} in the Accept Header." unless @@accept_formats.include? @@mime_format[mime_type]
        if mime_type =~ /json|yaml|uri-list/
          sparql = "SELECT DISTINCT ?g WHERE {GRAPH ?g {?s ?p ?o} }"
        elsif mime_type =~ /turtle|html|rdf|plain/
          sparql = "CONSTRUCT {?s ?p ?o.} WHERE {?s <#{RDF.type}> <#{klass}>; ?p ?o. }"
        end
        query sparql, mime_type
      end

      def self.get uri, mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.collect{|f| @@format_mime[f]}.join(", ")} in the Accept Header." unless @@accept_formats.include? @@mime_format[mime_type]
        not_found_error "#{uri} not found." unless available? uri
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE { ?s ?p ?o. }"
        query sparql, mime_type
      end

      def self.post uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.collect{|f| @@format_mime[f]}.join(", ")}." unless @@content_type_formats.include? @@mime_format[mime_type] or mime_type == "multipart/form-data"
        rdf = convert rdf, @@mime_format[mime_type], :ntriples
        rdf = "<#{uri}> <#{RDF.type}> <#{klass}>." unless rdf # create empty resource
        rdf += "\n<#{uri}> <#{RDF::DC.date}> \"#{DateTime.now}\"." unless rdf.match(%r{#{RDF::DC.date}})
        RestClient.post File.join(four_store_uri,"data")+"/", :data => rdf, :graph => uri, "mime-type" => "application/x-turtle" # not very consistent in 4store
      end

      def self.put uri, rdf, mime_type, skip_rewrite=false
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.collect{|f| @@format_mime[f]}.join(", ")}." unless @@content_type_formats.include? @@mime_format[mime_type]
        bad_request_error "Reqest body empty." unless rdf # create empty resource
        uuid = uri.sub(/\/$/,'').split('/').last
        bad_request_error "'#{uri}' is not a valid URI." unless uuid =~ /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/
        if !skip_rewrite
          rdf = convert rdf, @@mime_format[mime_type], :ntriples, uri 
        elsif mime_type != "text/plain" # ntriples are not converted
          rdf = convert rdf, @@mime_format[mime_type], :ntriples
        end
        RestClient.put File.join(four_store_uri,"data",uri), rdf, :content_type => "application/x-turtle" # content-type not very consistent in 4store
      end

      def self.delete uri
        RestClientWrapper.delete data_uri(uri)
      end

      def self.update sparql
        RestClient.post(update_uri, :update => sparql )
      end

      def self.query sparql, mime_type
        if sparql =~ /SELECT/i
          return RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => mime_type).body.gsub(/<|>/,'').split("\n") if mime_type == 'application/sparql-results+xml' 
          list = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body.gsub(/<|>/,'').split("\n")
          list.shift 
          return list unless mime_type
          case mime_type
          when /json/
            return list.to_json
          when /yaml/
            return list.to_yaml
          when /uri-list/
            return list.join "\n"
          else
            bad_request_error "#{mime_type} is not a supported mime type for SELECT statements. Please use one of text/uri-list, application/json, text/yaml, text/html."
          end
        elsif sparql =~ /CONSTRUCT/i
          nt = RestClient.get(sparql_uri, :params => { :query => sparql }, :accept => "text/plain").body
          return nt if mime_type == 'text/plain'
          case mime_type
          when /turtle/
            return convert(nt,:ntriples, :turtle)
          when /html/
            # TODO: fix and improve
            html = "<html><body>"
            html += convert(nt,:ntriples, :turtle).gsub(%r{<(.*)>},'&lt;<a href="\1">\1</a>&gt;').gsub(/\n/,'<br/>')
            html += "</body></html>"
            return html
          when "application/rdf+xml" 
            return convert(nt,:ntriples, :rdfxml)
          end
        else
          # TODO: check if this prevents SPARQL injections
          bad_request_error "Only SELECT and CONSTRUCT are accepted SPARQL statements."
        end
      end

      private

      def self.klass
        RDF::OT[SERVICE.capitalize]
      end

      def self.available? uri
        #sparql = "SELECT DISTINCT ?s WHERE {GRAPH <#{uri}> {?s ?p ?o} }"
        sparql = "SELECT DISTINCT ?s WHERE {GRAPH <#{uri}> {?s <#{RDF.type}> <#{klass}>} }"
        r = query(sparql, nil)
        r.size == 1 and r.first == uri
      end

      def self.convert rdf_string, input_format, output_format, rewrite_uri=nil
        rewrite_uri ?  serialize(parse_and_rewrite_uri(rdf_string,input_format, rewrite_uri), output_format) : serialize(parse(rdf_string,input_format), output_format)
      end

      def self.parse_and_rewrite_uri string, format, rewrite_uri
        rdf = RDF::Graph.new
        subject = nil
        statements = [] # use array instead of graph for performance reasons
        RDF::Reader.for(format).new(string) do |reader|
          reader.each_statement do |statement|
            subject = statement.subject if statement.predicate == RDF.type and statement.object == klass
            statements << statement
          end 
        end
        bad_request_error "No class specified with <#{RDF.type}> statement." unless subject
        statements.each do |statement|
          statement.subject = RDF::URI.new rewrite_uri if rewrite_uri and statement.subject == subject
          rdf << statement
        end
        rdf
      end

      def self.parse string, format
        rdf = RDF::Graph.new
        RDF::Reader.for(format).new(string) do |reader|
          reader.each_statement { |statement| rdf << statement }
        end
        rdf
      end

      def self.serialize rdf, format
        if format == :turtle # prefixes seen to need RDF::N3
          prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"}
          ['OT', 'DC', 'XSD'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
          string = RDF::N3::Writer.for(format).buffer(:prefixes => prefixes)  do |writer|
            rdf.each{|statement| writer << statement}
          end
        else
          string = RDF::Writer.for(format).buffer  do |writer|
            rdf.each{|statement| writer << statement}
          end
        end
        string
      end

      def self.four_store_uri
        # TODO remove credentials from URI 9security risk in tasks)
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
