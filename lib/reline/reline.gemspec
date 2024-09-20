
begin
  require_relative 'lib/reline/version'
rescue LoadError
  require_relative 'version'
end

Gem::Specification.new do |spec|
  spec.name          = 'reline'
  spec.version       = Reline::VERSION
  spec.authors       = ['aycabta']
  spec.email         = ['aycabta@gmail.com']

  spec.summary       = %q{Alternative GNU Readline or Editline implementation by pure Ruby.}
  spec.description   = %q{Alternative GNU Readline or Editline implementation by pure Ruby.}
  spec.homepage      = 'https://github.com/ruby/reline'
  spec.license       = 'Ruby'

  spec.files         = Dir['BSDL', 'COPYING', 'README.md', 'license_of_rb-readline', 'lib/**/*']
  spec.require_paths = ['lib']
  spec.metadata = {
    "bug_tracker_uri"   => "https://github.com/ruby/reline/issues",
    "changelog_uri"     => "https://github.com/ruby/reline/releases",
    "source_code_uri"   => "https://github.com/ruby/reline"
  }

  spec.required_ruby_version = Gem::Requirement.new('>= 2.6')

  spec.add_dependency 'io-console', '~> 0.5'
end
