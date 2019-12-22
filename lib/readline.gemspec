Gem::Specification.new do |spec|
  spec.name          = 'readline'
  spec.version       = '0.0.1.pre.1'
  spec.authors       = ['aycabta']
  spec.email         = ['aycabta@gmail.com']

  spec.summary       = %q{It's a loader for "readline".}
  spec.description   = <<~EOD
    This is just loader for "readline". If Ruby has "readline-ext" gem that
    is a native extension, this gem will load its first. If Ruby doesn't have
    the "readline-ext" gem this gem will load "reline" that is a compatible
    library with "readline-ext" gem and is implemented by pure Ruby.
  EOD
  spec.homepage      = 'https://github.com/ruby/readline'
  spec.license       = 'Ruby license'

  spec.files         = Dir['BSDL', 'COPYING', 'README.md', 'lib/readline.rb']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'reline'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
