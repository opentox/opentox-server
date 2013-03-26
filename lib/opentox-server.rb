require 'opentox-client'
require 'rack'
require 'rack/contrib'
require 'sinatra'
["4store.rb", "opentox.rb", "authorization-helper.rb"].each {|f| require File.join(File.dirname(__FILE__),f) }
