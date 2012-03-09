# set default environment
ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']

# load/setup configuration
basedir = File.join(ENV['HOME'], ".opentox")
config_dir = File.join(basedir, "config")
config_file = File.join(config_dir, "#{ENV['RACK_ENV']}.yaml")

TMP_DIR = File.join(basedir, "tmp")
LOG_DIR = File.join(basedir, "log")

=begin
if File.exist?(config_file)
	CONFIG = YAML.load_file(config_file)
  not_found_error "Could not load configuration from \"#{config_file.to_s}\"" unless CONFIG
else
	FileUtils.mkdir_p TMP_DIR
	FileUtils.mkdir_p LOG_DIR
	FileUtils.mkdir_p config_dir
	puts "Please edit #{config_file} and restart your application."
	exit
end
=end

logfile = "#{LOG_DIR}/#{ENV["RACK_ENV"]}.log"
$logger = OTLogger.new(logfile) 

=begin
if CONFIG[:logger] and CONFIG[:logger] == "debug"
	$logger.level = Logger::DEBUG
else
	$logger.level = Logger::WARN 
end

# TODO: move to opentox-client???
AA_SERVER = CONFIG[:authorization] ? (CONFIG[:authorization][:server] ? CONFIG[:authorization][:server] : nil) : nil
CONFIG[:authorization][:authenticate_request] = [""] unless CONFIG[:authorization][:authenticate_request]
CONFIG[:authorization][:authorize_request] =  [""] unless CONFIG[:authorization][:authorize_request]
CONFIG[:authorization][:free_request] =  [""] unless CONFIG[:authorization][:free_request]
=end

