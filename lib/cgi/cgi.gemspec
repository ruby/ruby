# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Support for the Common Gateway Interface protocol.}
  spec.description   = %q{Support for the Common Gateway Interface protocol.}
  spec.homepage      = "https://github.com/ruby/cgi"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.required_ruby_version = ">= 2.5.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{\A(?:(?:test|spec|features)/|\.git)}) }
  end
  spec.extensions    = ["ext/cgi/escape/extconf.rb"]
  spec.executables   = []
  spec.require_paths = ["lib"]
end
