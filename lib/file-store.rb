FileUtils.mkdir_p File.join(File.dirname(__FILE__),"private")

module OpenTox

  # Base class for OpenTox services
  class FileStore < Service 

    helpers do
      def next_id
        id = Dir["./private/*.nt"].collect{|f| File.basename(f,"nt").to_i}.sort.last
        id = 0 if id.nil?
        id + 1
      end

      def file id
        File.join File.dirname(File.expand_path __FILE__), "private", "#{id.to_s}.nt"
      end

      def uri_list
        Dir["./private/*.nt"].collect{|f| to(File.basename(f,".nt")}.join("\n"))
      end
    end

    get '/?' do
      uri_list
    end

    post '/?' do
      File.open(file(next_id),"w+"){|f| f.puts request.env["rack.input"].read}
    end

    get '/:id/?' do
      send_file file(params[:id])
    end
  end

end
