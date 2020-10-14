
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'reline/version'

Gem::Specification.new do |spec|
  spec.name          = 'reline'
  spec.version       = Reline::VERSION
  spec.authors       = ['aycabta']
  spec.email         = ['aycabta@gmail.com']

  spec.summary       = %q{Alternative GNU Readline or Editline implementation by pure Ruby.}
  spec.description   = %q{Alternative GNU Readline or Editline implementation by pure Ruby.}
  spec.homepage      = 'https://github.com/ruby/reline'
  spec.license       = 'Ruby'

  spec.files         = Dir['BSDL', 'COPYING', 'README.md', 'lib/**/*']
  spec.require_paths = ['lib']

  spec.required_ruby_version = Gem::Requirement.new('>= 2.5')

  spec.add_dependency 'io-console', '~> 0.5'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'test-unit'
  spec.add_development_dependency 'yamatanooroti', '>= 0.0.6'
end
