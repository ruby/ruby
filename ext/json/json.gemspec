# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "json"
  s.version = File.read('VERSION').chomp

  s.summary = "JSON Implementation for Ruby"
  s.description = "This is a JSON implementation as a Ruby extension in C."
  s.licenses = ["Ruby"]
  s.authors = ["Florian Frank"]
  s.email = "flori@ping.de"

  s.extensions = ["ext/json/ext/generator/extconf.rb", "ext/json/ext/parser/extconf.rb", "ext/json/extconf.rb"]
  s.extra_rdoc_files = ["README.md"]
  s.rdoc_options = ["--title", "JSON implementation for Ruby", "--main", "README.md"]
  s.files = [
    "CHANGES.md",
    "Gemfile",
    "LICENSE",
    "README.md",
    "VERSION",
    "ext/json/ext/fbuffer/fbuffer.h",
    "ext/json/ext/generator/depend",
    "ext/json/ext/generator/extconf.rb",
    "ext/json/ext/generator/generator.c",
    "ext/json/ext/generator/generator.h",
    "ext/json/ext/parser/depend",
    "ext/json/ext/parser/extconf.rb",
    "ext/json/ext/parser/parser.c",
    "ext/json/ext/parser/parser.h",
    "ext/json/ext/parser/parser.rl",
    "ext/json/extconf.rb",
    "json.gemspec",
    "lib/json.rb",
    "lib/json/add/bigdecimal.rb",
    "lib/json/add/complex.rb",
    "lib/json/add/core.rb",
    "lib/json/add/date.rb",
    "lib/json/add/date_time.rb",
    "lib/json/add/exception.rb",
    "lib/json/add/ostruct.rb",
    "lib/json/add/range.rb",
    "lib/json/add/rational.rb",
    "lib/json/add/regexp.rb",
    "lib/json/add/set.rb",
    "lib/json/add/struct.rb",
    "lib/json/add/symbol.rb",
    "lib/json/add/time.rb",
    "lib/json/common.rb",
    "lib/json/ext.rb",
    "lib/json/ext/.keep",
    "lib/json/generic_object.rb",
    "lib/json/pure.rb",
    "lib/json/pure/generator.rb",
    "lib/json/pure/parser.rb",
    "lib/json/version.rb",
  ] + Dir["tests/**/*"]
  s.homepage = "http://flori.github.com/json"
  s.metadata = {
    'bug_tracker_uri'   => 'https://github.com/flori/json/issues',
    'changelog_uri'     => 'https://github.com/flori/json/blob/master/CHANGES.md',
    'documentation_uri' => 'http://flori.github.io/json/doc/index.html',
    'homepage_uri'      => 'http://flori.github.io/json/',
    'source_code_uri'   => 'https://github.com/flori/json',
    'wiki_uri'          => 'https://github.com/flori/json/wiki'
  }

  s.required_ruby_version = Gem::Requirement.new(">= 2.0")
  s.test_files = ["tests/test_helper.rb"]

  s.add_development_dependency "rake"
  s.add_development_dependency "test-unit"
end
