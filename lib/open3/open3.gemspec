begin
  require_relative "lib/open3/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "open3"
  spec.version       = Open3::VERSION
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Popen, but with stderr, too}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/open3"
  spec.license       = "BSD-2-Clause"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
