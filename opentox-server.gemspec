# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "opentox-server"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma, Martin Guetlein, Andreas Maunz, Micha Rautenberg, David Vorgrimmler"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/opentox-server"
  s.summary     = %q{Ruby library for opentox services}
  s.description = %q{Ruby library for opentox services}
  s.license     = 'GPL-3'

  s.rubyforge_project = "opentox-server"

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-client"
  s.add_runtime_dependency 'rack'
  s.add_runtime_dependency 'rack-contrib', "= 1.2.0" # hotfix for issue with 1.3.0
  s.add_runtime_dependency 'rack-cors'
  s.add_runtime_dependency 'sinatra'
  s.add_runtime_dependency 'sinatra-contrib'
  s.add_runtime_dependency 'unicorn', "= 4.8.3"
end
