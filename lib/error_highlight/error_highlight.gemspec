# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
begin
  require_relative "lib/error_highlight/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "error_highlight"
  spec.version       = ErrorHighlight::VERSION
  spec.authors       = ["Yusuke Endoh"]
  spec.email         = ["mame@ruby-lang.org"]

  spec.summary       = 'Shows a one-line code snippet with an underline in the error backtrace'
  spec.description   = 'The gem enhances Exception#message by adding a short explanation where the exception is raised'
  spec.homepage      = "https://github.com/ruby/error_highlight"

  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0.dev")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]
end
