# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
require 'rdoc'

Gem::Specification.new do |s|
  s.name = "rdoc"
  s.version = RDoc::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 1.3")

  s.require_paths = ["lib"]
  s.authors = [
    "Eric Hodel",
    "Dave Thomas",
    "Phil Hagelberg",
    "Tony Strauss",
    "Zachary Scott",
    "Hiroshi SHIBATA"
  ]

  s.description = <<-DESCRIPTION
RDoc produces HTML and command-line documentation for Ruby projects.
RDoc includes the +rdoc+ and +ri+ tools for generating and displaying documentation from the command-line.
  DESCRIPTION

  s.email = ["drbrain@segment7.net", "mail@zzak.io", "hsbt@ruby-lang.org"]

  s.bindir = "exe"
  s.executables = ["rdoc", "ri"]

  s.extra_rdoc_files += %w[
    CVE-2013-0256.rdoc
    CONTRIBUTING.rdoc
    ExampleMarkdown.md
    ExampleRDoc.rdoc
    History.rdoc
    LEGAL.rdoc
    LICENSE.rdoc
    README.rdoc
    RI.rdoc
    TODO.rdoc
  ]

  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.files << "lib/rdoc/rd/block_parser.rb" << "lib/rdoc/rd/inline_parser.rb" << "lib/rdoc/markdown.rb"

  s.homepage = "http://docs.seattlerb.org/rdoc"
  s.licenses = ["Ruby"]

  s.rdoc_options = ["--main", "README.rdoc"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3")
  s.rubygems_version = "2.5.2"
  s.summary = "RDoc produces HTML and command-line documentation for Ruby projects"

  s.add_development_dependency("rake", "~> 10.5")
  s.add_development_dependency("racc", "~> 1.4", "> 1.4.10")
  s.add_development_dependency("kpeg", "~> 0.9")
  s.add_development_dependency("minitest", "~> 4")
end
