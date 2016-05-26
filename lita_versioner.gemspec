require_relative "lib/lita_versioner/version.rb"

Gem::Specification.new do |spec|
  spec.name          = "lita_versioner"
  spec.version       = LitaVersioner::VERSION
  spec.authors       = ["Serdar Sutay"]
  spec.email         = ["serdar@chef.io"]
  spec.description   = "Lita plugin to drive Jenkins per Github pull requests."
  spec.summary       = "Lita plugin to drive Jenkins per Github pull requests."
  spec.homepage      = "https://github.com/chef/lita_versioner"
  spec.license       = "Apache-2.0"
  spec.metadata      = { "lita_plugin_type" => "handler" }

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "lita", ">= 4.5"
  spec.add_runtime_dependency "mixlib-shellout"
  spec.add_runtime_dependency "ffi-yajl"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "pry-stack_explorer"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rspec", ">= 3.0.0"
end
