# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rdoc'

Gem::Specification.new do |s|
  s.name = "rdoc"
  s.version = RDoc::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 1.3") if
    s.respond_to? :required_rubygems_version=

  s.require_paths = ["lib"]
  s.authors = [
    "Eric Hodel",
    "Dave Thomas",
    "Phil Hagelberg",
    "Tony Strauss",
    "Zachary Scott"
  ]

  s.description = <<-DESCRIPTION
RDoc produces HTML and command-line documentation for Ruby projects.
RDoc includes the +rdoc+ and +ri+ tools for generating and displaying documentation from the command-line.
  DESCRIPTION

  s.email = ["drbrain@segment7.net", "mail@zzak.io"]

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

  s.files = File.readlines("Manifest.txt").map { |l| l.gsub("\n",'') }

  s.homepage = "http://docs.seattlerb.org/rdoc"
  s.licenses = ["Ruby"]
  s.post_install_message = <<-MESSAGE
Depending on your version of ruby, you may need to install ruby rdoc/ri data:

<= 1.8.6 : unsupported
 = 1.8.7 : gem install rdoc-data; rdoc-data --install
 = 1.9.1 : gem install rdoc-data; rdoc-data --install
>= 1.9.2 : nothing to do! Yay!
  MESSAGE

  s.rdoc_options = ["--main", "README.rdoc"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7")
  s.rubygems_version = "2.5.2"
  s.summary = "RDoc produces HTML and command-line documentation for Ruby projects"

  s.add_runtime_dependency("json", "~> 1.4")
  s.add_development_dependency("rake", "~> 10.5")
  s.add_development_dependency("racc", "~> 1.4", "> 1.4.10")
  s.add_development_dependency("kpeg", "~> 0.9")
  s.add_development_dependency("minitest", "~> 4")
end
