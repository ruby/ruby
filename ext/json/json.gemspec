# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "json"
  s.version = "2.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Florian Frank"]
  s.date = "2019-12-11"
  s.description = "This is a JSON implementation as a Ruby extension in C."
  s.email = "flori@ping.de"
  s.extensions = ["ext/json/ext/generator/extconf.rb", "ext/json/ext/parser/extconf.rb", "ext/json/extconf.rb"]
  s.extra_rdoc_files = ["README.md"]
  s.files = [
    ".gitignore",
    ".travis.yml",
    "CHANGES.md",
    "Gemfile",
    "README-json-jruby.md",
    "README.md",
    "Rakefile",
    "VERSION",
    "diagrams/.keep",
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
    "install.rb",
    "java/src/json/ext/ByteListTranscoder.java",
    "java/src/json/ext/Generator.java",
    "java/src/json/ext/GeneratorMethods.java",
    "java/src/json/ext/GeneratorService.java",
    "java/src/json/ext/GeneratorState.java",
    "java/src/json/ext/OptionsReader.java",
    "java/src/json/ext/Parser.java",
    "java/src/json/ext/Parser.rl",
    "java/src/json/ext/ParserService.java",
    "java/src/json/ext/RuntimeInfo.java",
    "java/src/json/ext/StringDecoder.java",
    "java/src/json/ext/StringEncoder.java",
    "java/src/json/ext/Utils.java",
    "json-java.gemspec",
    "json.gemspec",
    "json_pure.gemspec",
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
    "references/rfc7159.txt",
    "tests/fixtures/fail10.json",
    "tests/fixtures/fail11.json",
    "tests/fixtures/fail12.json",
    "tests/fixtures/fail13.json",
    "tests/fixtures/fail14.json",
    "tests/fixtures/fail18.json",
    "tests/fixtures/fail19.json",
    "tests/fixtures/fail2.json",
    "tests/fixtures/fail20.json",
    "tests/fixtures/fail21.json",
    "tests/fixtures/fail22.json",
    "tests/fixtures/fail23.json",
    "tests/fixtures/fail24.json",
    "tests/fixtures/fail25.json",
    "tests/fixtures/fail27.json",
    "tests/fixtures/fail28.json",
    "tests/fixtures/fail3.json",
    "tests/fixtures/fail4.json",
    "tests/fixtures/fail5.json",
    "tests/fixtures/fail6.json",
    "tests/fixtures/fail7.json",
    "tests/fixtures/fail8.json",
    "tests/fixtures/fail9.json",
    "tests/fixtures/obsolete_fail1.json",
    "tests/fixtures/pass1.json",
    "tests/fixtures/pass15.json",
    "tests/fixtures/pass16.json",
    "tests/fixtures/pass17.json",
    "tests/fixtures/pass2.json",
    "tests/fixtures/pass26.json",
    "tests/fixtures/pass3.json",
    "tests/json_addition_test.rb",
    "tests/json_common_interface_test.rb",
    "tests/json_encoding_test.rb",
    "tests/json_ext_parser_test.rb",
    "tests/json_fixtures_test.rb",
    "tests/json_generator_test.rb",
    "tests/json_generic_object_test.rb",
    "tests/json_parser_test.rb",
    "tests/json_string_matching_test.rb",
    "tests/test_helper.rb",
    "tests/test_helper.rb",
    "tools/diff.sh",
    "tools/fuzz.rb",
    "tools/server.rb",
  ]
  s.homepage = "http://flori.github.com/json"
  s.licenses = ["Ruby"]
  s.rdoc_options = ["--title", "JSON implemention for Ruby", "--main", "README.md"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9")
  s.rubygems_version = "3.0.3"
  s.summary = "JSON Implementation for Ruby"
  s.test_files = ["tests/test_helper.rb"]

  s.add_development_dependency("rake", [">= 0"])
  s.add_development_dependency("test-unit", ["~> 2.0"])
end
