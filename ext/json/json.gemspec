# -*- encoding: utf-8 -*-
# stub: json 2.1.0 ruby lib
# stub: ext/json/ext/generator/extconf.rb ext/json/ext/parser/extconf.rb ext/json/extconf.rb

Gem::Specification.new do |s|
  s.name = "json".freeze
  s.version = "2.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Florian Frank".freeze]
  s.date = "2017-04-18"
  s.description = "This is a JSON implementation as a Ruby extension in C.".freeze
  s.email = "flori@ping.de".freeze
  s.extensions = ["ext/json/ext/generator/extconf.rb".freeze, "ext/json/ext/parser/extconf.rb".freeze, "ext/json/extconf.rb".freeze]
  s.extra_rdoc_files = ["README.md".freeze]
  s.files = ["./tests/test_helper.rb".freeze, ".gitignore".freeze, ".travis.yml".freeze, "CHANGES.md".freeze, "Gemfile".freeze, "README-json-jruby.md".freeze, "README.md".freeze, "Rakefile".freeze, "VERSION".freeze, "data/example.json".freeze, "data/index.html".freeze, "data/prototype.js".freeze, "diagrams/.keep".freeze, "ext/json/ext/fbuffer/fbuffer.h".freeze, "ext/json/ext/generator/depend".freeze, "ext/json/ext/generator/extconf.rb".freeze, "ext/json/ext/generator/generator.c".freeze, "ext/json/ext/generator/generator.h".freeze, "ext/json/ext/parser/depend".freeze, "ext/json/ext/parser/extconf.rb".freeze, "ext/json/ext/parser/parser.c".freeze, "ext/json/ext/parser/parser.h".freeze, "ext/json/ext/parser/parser.rl".freeze, "ext/json/extconf.rb".freeze, "install.rb".freeze, "java/src/json/ext/ByteListTranscoder.java".freeze, "java/src/json/ext/Generator.java".freeze, "java/src/json/ext/GeneratorMethods.java".freeze, "java/src/json/ext/GeneratorService.java".freeze, "java/src/json/ext/GeneratorState.java".freeze, "java/src/json/ext/OptionsReader.java".freeze, "java/src/json/ext/Parser.java".freeze, "java/src/json/ext/Parser.rl".freeze, "java/src/json/ext/ParserService.java".freeze, "java/src/json/ext/RuntimeInfo.java".freeze, "java/src/json/ext/StringDecoder.java".freeze, "java/src/json/ext/StringEncoder.java".freeze, "java/src/json/ext/Utils.java".freeze, "json-java.gemspec".freeze, "json.gemspec".freeze, "json_pure.gemspec".freeze, "lib/json.rb".freeze, "lib/json/add/bigdecimal.rb".freeze, "lib/json/add/complex.rb".freeze, "lib/json/add/core.rb".freeze, "lib/json/add/date.rb".freeze, "lib/json/add/date_time.rb".freeze, "lib/json/add/exception.rb".freeze, "lib/json/add/ostruct.rb".freeze, "lib/json/add/range.rb".freeze, "lib/json/add/rational.rb".freeze, "lib/json/add/regexp.rb".freeze, "lib/json/add/struct.rb".freeze, "lib/json/add/symbol.rb".freeze, "lib/json/add/time.rb".freeze, "lib/json/common.rb".freeze, "lib/json/ext.rb".freeze, "lib/json/ext/.keep".freeze, "lib/json/generic_object.rb".freeze, "lib/json/pure.rb".freeze, "lib/json/pure/generator.rb".freeze, "lib/json/pure/parser.rb".freeze, "lib/json/version.rb".freeze, "references/rfc7159.txt".freeze, "tests/fixtures/fail10.json".freeze, "tests/fixtures/fail11.json".freeze, "tests/fixtures/fail12.json".freeze, "tests/fixtures/fail13.json".freeze, "tests/fixtures/fail14.json".freeze, "tests/fixtures/fail18.json".freeze, "tests/fixtures/fail19.json".freeze, "tests/fixtures/fail2.json".freeze, "tests/fixtures/fail20.json".freeze, "tests/fixtures/fail21.json".freeze, "tests/fixtures/fail22.json".freeze, "tests/fixtures/fail23.json".freeze, "tests/fixtures/fail24.json".freeze, "tests/fixtures/fail25.json".freeze, "tests/fixtures/fail27.json".freeze, "tests/fixtures/fail28.json".freeze, "tests/fixtures/fail3.json".freeze, "tests/fixtures/fail4.json".freeze, "tests/fixtures/fail5.json".freeze, "tests/fixtures/fail6.json".freeze, "tests/fixtures/fail7.json".freeze, "tests/fixtures/fail8.json".freeze, "tests/fixtures/fail9.json".freeze, "tests/fixtures/obsolete_fail1.json".freeze, "tests/fixtures/pass1.json".freeze, "tests/fixtures/pass15.json".freeze, "tests/fixtures/pass16.json".freeze, "tests/fixtures/pass17.json".freeze, "tests/fixtures/pass2.json".freeze, "tests/fixtures/pass26.json".freeze, "tests/fixtures/pass3.json".freeze, "tests/json_addition_test.rb".freeze, "tests/json_common_interface_test.rb".freeze, "tests/json_encoding_test.rb".freeze, "tests/json_ext_parser_test.rb".freeze, "tests/json_fixtures_test.rb".freeze, "tests/json_generator_test.rb".freeze, "tests/json_generic_object_test.rb".freeze, "tests/json_parser_test.rb".freeze, "tests/json_string_matching_test.rb".freeze, "tests/test_helper.rb".freeze, "tools/diff.sh".freeze, "tools/fuzz.rb".freeze, "tools/server.rb".freeze]
  s.homepage = "http://flori.github.com/json".freeze
  s.licenses = ["Ruby".freeze]
  s.rdoc_options = ["--title".freeze, "JSON implemention for Ruby".freeze, "--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9".freeze)
  s.rubygems_version = "2.6.11".freeze
  s.summary = "JSON Implementation for Ruby".freeze
  s.test_files = ["./tests/test_helper.rb".freeze]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
      s.add_development_dependency(%q<test-unit>.freeze, ["~> 2.0"])
    else
      s.add_dependency(%q<rake>.freeze, [">= 0"])
      s.add_dependency(%q<test-unit>.freeze, ["~> 2.0"])
    end
  else
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<test-unit>.freeze, ["~> 2.0"])
  end
end
