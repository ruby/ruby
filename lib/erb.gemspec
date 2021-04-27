begin
  require_relative 'lib/erb/version'
rescue LoadError
  # for Ruby core repository
  require_relative 'erb/version'
end

Gem::Specification.new do |spec|
  spec.name          = 'erb'
  spec.version       = ERB.const_get(:VERSION, false)
  spec.authors       = ['Masatoshi SEKI']
  spec.email         = ['seki@ruby-lang.org']

  spec.summary       = %q{An easy to use but powerful templating system for Ruby.}
  spec.description   = %q{An easy to use but powerful templating system for Ruby.}
  spec.homepage      = 'https://github.com/ruby/erb'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.5.0')
  spec.licenses      = ['Ruby', 'BSD-2-Clause']

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'libexec'
  spec.executables   = ['erb']
  spec.require_paths = ['lib']

  spec.add_dependency 'cgi'
end
