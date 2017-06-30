# -*- encoding: utf-8 -*-
# stub: psych 2.1.0 ruby lib
# stub: ext/psych/extconf.rb

Gem::Specification.new do |s|
  s.name = "psych"
  s.version = "2.1.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Aaron Patterson"]
  s.date = "2016-06-24"
  s.description = "Psych is a YAML parser and emitter.  Psych leverages libyaml[http://pyyaml.org/wiki/LibYAML]\nfor its YAML parsing and emitting capabilities.  In addition to wrapping\nlibyaml, Psych also knows how to serialize and de-serialize most Ruby objects\nto and from the YAML format."
  s.email = ["aaron@tenderlovemaking.com"]
  s.extensions = ["ext/psych/extconf.rb"]
  s.extra_rdoc_files = ["CHANGELOG.rdoc", "Manifest.txt", "README.rdoc", "CHANGELOG.rdoc", "README.rdoc"]
  s.files = [".autotest", ".travis.yml", "CHANGELOG.rdoc", "Manifest.txt", "README.rdoc", "Rakefile", "ext/psych/depend", "ext/psych/extconf.rb", "ext/psych/psych.c", "ext/psych/psych.h", "ext/psych/psych_emitter.c", "ext/psych/psych_emitter.h", "ext/psych/psych_parser.c", "ext/psych/psych_parser.h", "ext/psych/psych_to_ruby.c", "ext/psych/psych_to_ruby.h", "ext/psych/psych_yaml_tree.c", "ext/psych/psych_yaml_tree.h", "ext/psych/yaml/LICENSE", "ext/psych/yaml/api.c", "ext/psych/yaml/config.h", "ext/psych/yaml/dumper.c", "ext/psych/yaml/emitter.c", "ext/psych/yaml/loader.c", "ext/psych/yaml/parser.c", "ext/psych/yaml/reader.c", "ext/psych/yaml/scanner.c", "ext/psych/yaml/writer.c", "ext/psych/yaml/yaml.h", "ext/psych/yaml/yaml_private.h", "lib/psych.rb", "lib/psych/class_loader.rb", "lib/psych/coder.rb", "lib/psych/core_ext.rb", "lib/psych/deprecated.rb", "lib/psych/exception.rb", "lib/psych/handler.rb", "lib/psych/handlers/document_stream.rb", "lib/psych/handlers/recorder.rb", "lib/psych/json/ruby_events.rb", "lib/psych/json/stream.rb", "lib/psych/json/tree_builder.rb", "lib/psych/json/yaml_events.rb", "lib/psych/nodes.rb", "lib/psych/nodes/alias.rb", "lib/psych/nodes/document.rb", "lib/psych/nodes/mapping.rb", "lib/psych/nodes/node.rb", "lib/psych/nodes/scalar.rb", "lib/psych/nodes/sequence.rb", "lib/psych/nodes/stream.rb", "lib/psych/omap.rb", "lib/psych/parser.rb", "lib/psych/scalar_scanner.rb", "lib/psych/set.rb", "lib/psych/stream.rb", "lib/psych/streaming.rb", "lib/psych/syntax_error.rb", "lib/psych/tree_builder.rb", "lib/psych/versions.rb", "lib/psych/visitors.rb", "lib/psych/visitors/depth_first.rb", "lib/psych/visitors/emitter.rb", "lib/psych/visitors/json_tree.rb", "lib/psych/visitors/to_ruby.rb", "lib/psych/visitors/visitor.rb", "lib/psych/visitors/yaml_tree.rb", "lib/psych/y.rb", "lib/psych_jars.rb", "test/psych/handlers/test_recorder.rb", "test/psych/helper.rb", "test/psych/json/test_stream.rb", "test/psych/nodes/test_enumerable.rb", "test/psych/test_alias_and_anchor.rb", "test/psych/test_array.rb", "test/psych/test_boolean.rb", "test/psych/test_class.rb", "test/psych/test_coder.rb", "test/psych/test_date_time.rb", "test/psych/test_deprecated.rb", "test/psych/test_document.rb", "test/psych/test_emitter.rb", "test/psych/test_encoding.rb", "test/psych/test_exception.rb", "test/psych/test_hash.rb", "test/psych/test_json_tree.rb", "test/psych/test_merge_keys.rb", "test/psych/test_nil.rb", "test/psych/test_null.rb", "test/psych/test_numeric.rb", "test/psych/test_object.rb", "test/psych/test_object_references.rb", "test/psych/test_omap.rb", "test/psych/test_parser.rb", "test/psych/test_psych.rb", "test/psych/test_safe_load.rb", "test/psych/test_scalar.rb", "test/psych/test_scalar_scanner.rb", "test/psych/test_serialize_subclasses.rb", "test/psych/test_set.rb", "test/psych/test_stream.rb", "test/psych/test_string.rb", "test/psych/test_struct.rb", "test/psych/test_symbol.rb", "test/psych/test_tainted.rb", "test/psych/test_to_yaml_properties.rb", "test/psych/test_tree_builder.rb", "test/psych/test_yaml.rb", "test/psych/test_yamldbm.rb", "test/psych/test_yamlstore.rb", "test/psych/visitors/test_depth_first.rb", "test/psych/visitors/test_emitter.rb", "test/psych/visitors/test_to_ruby.rb", "test/psych/visitors/test_yaml_tree.rb"]
  s.homepage = "http://github.com/tenderlove/psych"
  s.licenses = ["MIT"]
  s.rdoc_options = ["--main", "README.rdoc"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.2")
  s.rubygems_version = "2.5.1"
  s.summary = "Psych is a YAML parser and emitter"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_development_dependency(%q<rake-compiler>, [">= 0.4.1"])
      s.add_development_dependency(%q<minitest>, ["~> 5.0"])
      s.add_development_dependency(%q<hoe>, ["~> 3.15"])
    else
      s.add_dependency(%q<rdoc>, ["~> 4.0"])
      s.add_dependency(%q<rake-compiler>, [">= 0.4.1"])
      s.add_dependency(%q<minitest>, ["~> 5.0"])
      s.add_dependency(%q<hoe>, ["~> 3.15"])
    end
  else
    s.add_dependency(%q<rdoc>, ["~> 4.0"])
    s.add_dependency(%q<rake-compiler>, [">= 0.4.1"])
    s.add_dependency(%q<minitest>, ["~> 5.0"])
    s.add_dependency(%q<hoe>, ["~> 3.15"])
  end
end
