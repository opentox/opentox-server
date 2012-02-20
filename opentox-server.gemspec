# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "opentox-server/version"

Gem::Specification.new do |s|
  s.name        = "opentox-server"
  s.version     = Opentox::Server::VERSION
  s.authors     = ["Christoph Helma"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = ""
  s.summary     = %q{Ruby library for opentox services}
  s.description = %q{Ruby library for opentox services}

  s.rubyforge_project = "opentox-server"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-client"
  s.add_runtime_dependency 'rack'
  s.add_runtime_dependency 'rack-contrib'
  s.add_runtime_dependency 'sinatra'
  s.add_runtime_dependency 'emk-sinatra-url-for'
  s.add_runtime_dependency 'spreadsheet'
  s.add_runtime_dependency 'roo'
end
