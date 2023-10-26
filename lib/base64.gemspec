name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1).join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Yusuke Endoh"]
  spec.email         = ["mame@ruby-lang.org"]

  spec.summary       = %q{Support for encoding and decoding binary data using a Base64 representation.}
  spec.description   = %q{Support for encoding and decoding binary data using a Base64 representation.}
  spec.homepage      = "https://github.com/ruby/base64"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = ["README.md", "LICENSE.txt", "lib/base64.rb"]
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
