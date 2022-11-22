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

  spec.executables   = []

  spec.files = [
    "LICENSE.txt",
    "README.md",
    *Dir["lib{.rb,/**/*.rb}", "bin/*"]  ]

  spec.require_paths = ["lib"]

  if Gem::Platform === spec.platform and spec.platform =~ 'java' or RUBY_ENGINE == 'jruby'
    spec.platform = 'java'
    spec.require_paths << "ext/java/org/jruby/ext/cgi/escape/lib"
    spec.files += Dir["ext/java/**/*.{rb}", "lib/cgi/escape.jar"]
  else
    spec.files += Dir["ext/cgi/**/*.{rb,c,h,sh}", "ext/cgi/escape/depend", "lib/cgi/escape.so"]
    spec.extensions    = ["ext/cgi/escape/extconf.rb"]
  end
end
