Gem::Specification.new do |spec|
  spec.name          = 'readline'
  spec.version       = '0.0.2'
  spec.authors       = ['aycabta']
  spec.email         = ['aycabta@gmail.com']

  spec.summary       = %q{It's a loader for "readline".}
  spec.description   = <<~EOD
    This is just a loader for "readline". If Ruby has "readline-ext" gem that
    is a native extension, this gem will load it first. If Ruby doesn't have
    the "readline-ext" gem this gem will load "reline" that is a compatible
    library with "readline-ext" gem and is implemented by pure Ruby.
  EOD
  spec.homepage      = 'https://github.com/ruby/readline'
  spec.license       = 'Ruby'

  spec.files         = Dir['BSDL', 'COPYING', 'README.md', 'lib/readline.rb']
  spec.require_paths = ['lib']

  spec.post_install_message = <<~EOM
    +---------------------------------------------------------------------------+
    | This is just a loader for "readline". If Ruby has "readline-ext" gem that |
    | is a native extension, this gem will load it first. If Ruby doesn't have  |
    | the "readline-ext" gem this gem will load "reline" that is a compatible   |
    | library with "readline-ext" gem and is implemented by pure Ruby.          |
    |                                                                           |
    | If you intend to use GNU Readline by `require 'readline'`, please install |
    | "readline-ext" gem.                                                       |
    +---------------------------------------------------------------------------+
  EOM

  spec.add_runtime_dependency 'reline'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
