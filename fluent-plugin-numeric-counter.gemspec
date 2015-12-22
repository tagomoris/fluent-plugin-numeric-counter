# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-numeric-counter"
  gem.version       = "0.2.3"
  gem.authors       = ["TAGOMORI Satoshi"]
  gem.email         = ["tagomoris@gmail.com"]
  gem.description   = %q{Counts messages, with specified key and numeric value in specified range}
  gem.summary       = %q{Fluentd plugin to count messages with specified numeric values}
  gem.homepage      = "https://github.com/tagomoris/fluent-plugin-numeric-counter"
  gem.license       = "APLv2"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "rake"
  gem.add_development_dependency "delorean"
  gem.add_development_dependency "test-unit", ">= 3.1.0"
  gem.add_runtime_dependency "fluentd"
end
