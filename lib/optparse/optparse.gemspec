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
  spec.description   = File.open(File.join(__dir__, "README.md")) do |readme|
    readme.gets("") # heading
    readme.gets("").chomp
  end rescue spec.summary
  spec.homepage      = "https://github.com/ruby/optparse"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  dir, gemspec = File.split(__FILE__)
  excludes = %W[#{gemspec} rakelib test/ Gemfile Rakefile .git* .editor*].map {|n| ":^"+n}
  spec.files = IO.popen(%w[git ls-files -z --] + excludes, chdir: dir, &:read).split("\x0")
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
