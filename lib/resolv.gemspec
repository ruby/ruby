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

  spec.summary       = %q{Thread-aware DNS resolver library in Ruby.}
  spec.description   = %q{Thread-aware DNS resolver library in Ruby.}
  spec.homepage      = "https://github.com/ruby/resolv"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.extensions << "ext/win32/resolv/extconf.rb"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  excludes = %W[/.git* /bin /test /*file /#{File.basename(__FILE__)}]
  spec.files = IO.popen(%W[git -C #{__dir__} ls-files -z --] + excludes.map {|e| ":^#{e}"}, &:read).split("\x0")
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
