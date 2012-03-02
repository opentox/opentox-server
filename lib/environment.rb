# set default environment

ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']

# load/setup configuration
basedir = File.join(ENV['HOME'], ".opentox")
config_dir = File.join(basedir, "config")
config_file = File.join(config_dir, "#{ENV['RACK_ENV']}.yaml")

TMP_DIR = File.join(basedir, "tmp")
LOG_DIR = File.join(basedir, "log")

if File.exist?(config_file)
	CONFIG = YAML.load_file(config_file)
  raise "could not load config, config file: "+config_file.to_s unless CONFIG
else
	FileUtils.mkdir_p TMP_DIR
	FileUtils.mkdir_p LOG_DIR
	FileUtils.mkdir_p config_dir
	puts "Please edit #{config_file} and restart your application."
	#exit
end

logfile = "#{LOG_DIR}/#{ENV["RACK_ENV"]}.log"

$logger = OTLogger.new(logfile) # no rotation
$logger.formatter = Logger::Formatter.new #this is neccessary to restore the formating in case active-record is loaded
if CONFIG[:logger] and CONFIG[:logger] == "debug"
	$logger.level = Logger::DEBUG
else
	$logger.level = Logger::WARN 
end

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox|activating|carcinogen|mutagenic)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox|deactivating|non-carcinogen|non-mutagenic)$/i

AA_SERVER = CONFIG[:authorization] ? (CONFIG[:authorization][:server] ? CONFIG[:authorization][:server] : nil) : nil
CONFIG[:authorization][:authenticate_request] = [""] unless CONFIG[:authorization][:authenticate_request]
CONFIG[:authorization][:authorize_request] =  [""] unless CONFIG[:authorization][:authorize_request]
CONFIG[:authorization][:free_request] =  [""] unless CONFIG[:authorization][:free_request]

