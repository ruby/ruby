name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*LOADER_VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Aaron Patterson", "SHIBATA Hiroshi"]
  spec.email         = ["aaron@tenderlovemaking.com", "hsbt@ruby-lang.org"]

  spec.summary       = "YAML Ain't Markup Language"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/yaml"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>#{IO::NULL}`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
