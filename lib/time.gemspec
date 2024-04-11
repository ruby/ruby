name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1).join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Tanaka Akira"]
  spec.email         = ["akr@fsij.org"]

  spec.summary       = %q{Extends the Time class with methods for parsing and conversion.}
  spec.description   = %q{Extends the Time class with methods for parsing and conversion.}
  spec.homepage      = "https://github.com/ruby/time"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  srcdir, gemspec = File.split(__FILE__)
  spec.files         = Dir.chdir(srcdir) do
    `git ls-files -z`.split("\x0").reject { |f|
      f == gemspec or
        f.start_with?(".git", "bin/", "test/", "rakelib/", "Gemfile", "Rakefile")
    }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "date"
end
