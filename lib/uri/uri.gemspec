begin
  require_relative "lib/uri/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "uri"
  spec.version       = URI::VERSION
  spec.authors       = ["Akira Yamada"]
  spec.email         = ["akira@ruby-lang.org"]

  spec.summary       = %q{URI is a module providing classes to handle Uniform Resource Identifiers}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/uri"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.required_ruby_version = '>= 2.4'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
