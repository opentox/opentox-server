module OpenTox
  module Backend
    class FourStore

      # TODO: simplify
      @@mime_format = {
        "application/rdf+xml" => :rdfxml,
        "text/turtle" => :turtle,
        "text/plain" => :ntriples,
        "text/uri-list" => :uri_list,
        "text/html" => :html,
        'application/sparql-results+xml' => :sparql
      }

      @@format_mime = {
        :rdfxml => "application/rdf+xml", 
        :turtle => "text/turtle",
        :ntriples => "text/plain",
        :uri_list => "text/uri-list",
        :html => "text/html",
        :sparql => 'application/sparql-results+xml'
      }

      @@accept_formats = [:rdfxml, :turtle, :ntriples, :uri_list, :html, :sparql] 
      @@content_type_formats = [:rdfxml, :turtle, :ntriples]

      def self.list mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        if mime_type =~ /uri-list/
          sparql = "SELECT DISTINCT ?g WHERE {GRAPH ?g {?s ?p ?o} }"
        elsif mime_type =~ /turtle|html|rdf|plain/
          sparql = "CONSTRUCT {?s ?p ?o.} WHERE {?s <#{RDF.type}> <#{klass}>; ?p ?o. }"
        else
          bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.collect{|f| @@format_mime[f]}.join(", ")} in the Accept Header." #unless @@accept_formats.include? @@mime_format[mime_type]
        end
        query sparql, mime_type
      end

      def self.get uri, mime_type
        mime_type = "text/html" if mime_type.match(%r{\*/\*})
        bad_request_error "'#{mime_type}' is not a supported mime type. Please specify one of #{@@accept_formats.collect{|f| @@format_mime[f]}.join(", ")} in the Accept Header." unless @@accept_formats.include? @@mime_format[mime_type]
        sparql = "CONSTRUCT {?s ?p ?o.} FROM <#{uri}> WHERE { ?s ?p ?o. }"
        rdf = query sparql, mime_type
        not_found_error "#{uri} not found." if rdf.empty?
        rdf
      end

      def self.post uri, rdf, mime_type
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.collect{|f| @@format_mime[f]}.join(", ")}." unless @@content_type_formats.include? @@mime_format[mime_type] or mime_type == "multipart/form-data"
        bad_request_error "Reqest body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain" # ntriples is turtle in 4store
        RestClient.post File.join(four_store_uri,"data")+"/", :data => rdf, :graph => uri, "mime-type" => mime_type 
      end

      def self.put uri, rdf, mime_type, skip_rewrite=false
        bad_request_error "'#{mime_type}' is not a supported content type. Please use one of #{@@content_type_formats.collect{|f| @@format_mime[f]}.join(", ")}." unless @@content_type_formats.include? @@mime_format[mime_type]
        bad_request_error "Reqest body empty." unless rdf 
        mime_type = "application/x-turtle" if mime_type == "text/plain"
        RestClient.put File.join(four_store_uri,"data",uri), rdf, :content_type => mime_type # content-type not very consistent in 4store
      end

      def self.delete uri
        RestClientWrapper.delete data_uri(uri)
      end

      def self.update sparql
        RestClient.post(update_uri, :update => sparql )
      end

      def self.query sparql, mime_type
        if sparql =~ /SELECT/i
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
            ['OT', 'DC', 'XSD'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
            turtle = RDF::N3::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
              rdf.each{|statement| writer << statement}
            end
            turtle =  "<html><body>" + turtle.gsub(%r{<(.*)>},'&lt;<a href="\1">\1</a>&gt;').gsub(/\n/,'<br/>') + "</body></html>" if mime_type =~ /html/ and !turtle.empty?
            turtle
          end
        else
          # TODO: check if this prevents SPARQL injections
          bad_request_error "Only SELECT and CONSTRUCT are accepted SPARQL statements."
        end
      end

      def self.klass
        RDF::OT[SERVICE.capitalize]
      end

=begin
      def self.available? uri
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
          if rewrite_uri 
            statement.subject = RDF::URI.new rewrite_uri if statement.subject.to_s == subject
            statement.object = RDF::URI.new rewrite_uri if statement.predicate == RDF::XSD.anyURI
          end
          rdf << statement
        end
        rdf
      end
=end

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
