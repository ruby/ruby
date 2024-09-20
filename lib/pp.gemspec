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

  spec.summary       = %q{Provides a PrettyPrinter for Ruby objects}
  spec.description   = %q{Provides a PrettyPrinter for Ruby objects}
  spec.homepage      = "https://github.com/ruby/pp"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = %w[
    LICENSE.txt
    lib/pp.rb
    pp.gemspec
  ]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prettyprint"
end
