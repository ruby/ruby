# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "psych"
  s.version = "2.1.1"
  s.authors = ["Aaron Patterson", "SHIBATA Hiroshi"]
  s.email = ["aaron@tenderlovemaking.com", "hsbt@ruby-lang.org"]
  s.date = "2016-09-07"
  s.summary = "Psych is a YAML parser and emitter"
  s.description = <<-DESCRIPTION
Psych is a YAML parser and emitter. Psych leverages libyaml[http://pyyaml.org/wiki/LibYAML]
for its YAML parsing and emitting capabilities. In addition to wrapping libyaml,
Psych also knows how to serialize and de-serialize most Ruby objects to and from the YAML format.
DESCRIPTION
  s.homepage = "http://github.com/tenderlove/psych"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  s.rdoc_options = ["--main", "README.rdoc"]
  s.extra_rdoc_files = ["CHANGELOG.rdoc", "README.rdoc", "CHANGELOG.rdoc", "README.rdoc"]

  s.required_ruby_version = Gem::Requirement.new(">= 1.9.2")
  s.rubygems_version = "2.5.1"
  s.required_rubygems_version = Gem::Requirement.new(">= 0")

  s.add_development_dependency(%q<rake-compiler>, [">= 0.4.1"])
  s.add_development_dependency(%q<minitest>, ["~> 5.0"])

  if RUBY_PLATFORM =~ /java/
    require 'psych/versions'
    s.platform = 'java'
    s.requirements = "jar org.yaml:snakeyaml, #{Psych::DEFAULT_SNAKEYAML_VERSION}"
    s.add_dependency 'jar-dependencies', '>= 0.1.7'
    s.add_development_dependency 'ruby-maven'
  else
    s.extensions = ["ext/psych/extconf.rb"]
  end
end
