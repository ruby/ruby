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

  spec.summary       = %q{Topological sorting using Tarjan's algorithm}
  spec.description   = %q{Topological sorting using Tarjan's algorithm}
  spec.homepage      = "https://github.com/ruby/tsort"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  dir, gemspec = File.split(__FILE__)
  excludes = %W[
    :^/bin/ :^/test/ :^/spec/ :^/features/ :^/Gemfile :^/Rakefile
  ]
  spec.files = IO.popen(%w[git ls-files -z --] + excludes, chdir: dir) do |f|
    f.read.split("\x0")
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
