# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*OptionParser::Version\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Nobu Nakada"]
  spec.email         = ["nobu@ruby-lang.org"]

  spec.summary       = %q{OptionParser is a class for command-line option analysis.}
  spec.description   = %q{OptionParser is a class for command-line option analysis.}
  spec.homepage      = "https://github.com/ruby/optparse"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir["{doc,lib,misc}/**/*"] + %w[README.md ChangeLog COPYING]
  spec.rdoc_options  = ["--main=README.md", "--op=rdoc", "--page-dir=doc"]
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
