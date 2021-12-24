Gem::Specification.new do |spec|
  spec.name          = 'readline'
  spec.version       = '0.0.3'
  spec.authors       = ['aycabta']
  spec.email         = ['aycabta@gmail.com']

  spec.summary       = %q{Loader for "readline".}
  spec.description   = <<~EOD
    This is just a loader for "readline". If Ruby has the "readline-ext" gem
    that is a native extension, this gem will load it. If Ruby does not have
    the "readline-ext" gem this gem will load "reline", a library that is
    compatible with the "readline-ext" gem and implemented in pure Ruby.
  EOD
  spec.homepage      = 'https://github.com/ruby/readline'
  spec.license       = 'Ruby'

  spec.files         = Dir['BSDL', 'COPYING', 'README.md', 'lib/readline.rb']
  spec.require_paths = ['lib']

  spec.post_install_message = <<~EOM
    +---------------------------------------------------------------------------+
    | This is just a loader for "readline". If Ruby has the "readline-ext" gem  |
    | that is a native extension, this gem will load it. If Ruby does not have  |
    | the "readline-ext" gem this gem will load "reline", a library that is     |
    | compatible with the "readline-ext" gem and implemented in pure Ruby.      |
    |                                                                           |
    | If you intend to use GNU Readline by `require 'readline'`, please install |
    | the "readline-ext" gem.                                                   |
    +---------------------------------------------------------------------------+
  EOM

  spec.add_runtime_dependency 'reline'
end
