# frozen_string_literal: true

require_relative "helper"

Gem.load_yaml

class TestGemSafeYAML < Gem::TestCase
  def test_aliases_enabled_by_default
    pend "Psych is not loaded" if defined?(Gem::YAMLSerializer)
    assert_predicate Gem::SafeYAML, :aliases_enabled?
    assert_equal({ "a" => "a", "b" => "a" }, Gem::SafeYAML.safe_load("a: &a a\nb: *a\n"))
  end

  def test_aliases_disabled
    pend "Psych is not loaded" if defined?(Gem::YAMLSerializer)
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = false
    refute_predicate Gem::SafeYAML, :aliases_enabled?
    expected_error = defined?(Psych::AliasesNotEnabled) ? Psych::AliasesNotEnabled : Psych::BadAlias
    assert_raise expected_error do
      Gem::SafeYAML.safe_load("a: &a\nb: *a\n")
    end
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_specification_version_is_integer
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test
      version: !ruby/object:Gem::Version
        version: 1.0.0
      specification_version: 4
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Integer, spec.specification_version
    assert_equal 4, spec.specification_version
  end

  def test_disallowed_class_rejected
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:SomeDisallowedClass
      foo: bar
    YAML

    exception = assert_raise(ArgumentError) do
      Gem::SafeYAML.safe_load(yaml)
    end
    assert_match(/Disallowed class/, exception.message)
  end

  def test_disallowed_symbol_rejected
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:Gem::Dependency
      name: test
      requirement: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: 0
      type: :invalid_type
      prerelease: false
      version_requirements: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: 0
    YAML

    exception = assert_raise(ArgumentError) do
      Gem::SafeYAML.safe_load(yaml)
    end
    assert_match(/Disallowed symbol/, exception.message)
  end

  def test_yaml_serializer_aliases_disabled
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = false
    refute_predicate Gem::SafeYAML, :aliases_enabled?

    yaml = "a: &anchor value\nb: *anchor\n"

    exception = assert_raise(ArgumentError) do
      Gem::SafeYAML.safe_load(yaml)
    end
    assert_match(/YAML aliases are not allowed/, exception.message)
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_real_gemspec_fileutils
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: fileutils
      version: !ruby/object:Gem::Version
        version: 1.8.0
      platform: ruby
      authors:
      - Minero Aoki
      bindir: bin
      cert_chain: []
      date: 1980-01-02 00:00:00.000000000 Z
      dependencies: []
      description: Several file utility methods for copying, moving, removing, etc.
      email:
      -
      executables: []
      extensions: []
      extra_rdoc_files: []
      files:
      - BSDL
      - COPYING
      - README.md
      - Rakefile
      - fileutils.gemspec
      - lib/fileutils.rb
      homepage: https://github.com/ruby/fileutils
      licenses:
      - Ruby
      - BSD-2-Clause
      metadata:
        source_code_uri: https://github.com/ruby/fileutils
      rdoc_options: []
      require_paths:
      - lib
      required_ruby_version: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: 2.5.0
      required_rubygems_version: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: '0'
      requirements: []
      rubygems_version: 3.6.9
      specification_version: 4
      summary: Several file utility methods for copying, moving, removing, etc.
      test_files: []
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "fileutils", spec.name
    assert_equal Gem::Version.new("1.8.0"), spec.version
    assert_kind_of Integer, spec.specification_version
    assert_equal 4, spec.specification_version
  end

  def test_yaml_anchor_and_alias_enabled
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = true

    yaml = <<~YAML
      dependencies:
      - &req !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: '0'
      - *req
    YAML

    result = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Hash, result
    assert_kind_of Array, result["dependencies"]
    assert_equal 2, result["dependencies"].size
    assert_kind_of Gem::Requirement, result["dependencies"][0]
    assert_kind_of Gem::Requirement, result["dependencies"][1]
    assert_equal result["dependencies"][0].requirements, result["dependencies"][1].requirements
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_real_gemspec_rubygems_bundler
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: rubygems-bundler
      version: !ruby/object:Gem::Version
        version: 1.4.5
      platform: ruby
      authors:
      - Josh Hull
      - Michal Papis
      autorequire:
      bindir: bin
      cert_chain: []
      date: 2018-06-24 00:00:00.000000000 Z
      dependencies:
      - !ruby/object:Gem::Dependency
        name: bundler-unload
        requirement: !ruby/object:Gem::Requirement
          requirements:
          - - ">="
            - !ruby/object:Gem::Version
              version: 1.0.2
        type: :runtime
        prerelease: false
        version_requirements: !ruby/object:Gem::Requirement
          requirements:
          - - ">="
            - !ruby/object:Gem::Version
              version: 1.0.2
      description: Stop using bundle exec.
      email:
      - joshbuddy@gmail.com
      - mpapis@gmail.com
      executables: []
      extensions: []
      extra_rdoc_files: []
      files:
      - ".gem.config"
      homepage: http://mpapis.github.com/rubygems-bundler
      licenses:
      - Apache-2.0
      metadata: {}
      post_install_message:
      rdoc_options: []
      require_paths:
      - lib
      required_ruby_version: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: '0'
      rubyforge_project:
      rubygems_version: 2.7.6
      signing_key:
      specification_version: 4
      summary: Stop using bundle exec
      test_files: []
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "rubygems-bundler", spec.name
    assert_equal Gem::Version.new("1.4.5"), spec.version
    assert_equal 1, spec.dependencies.size

    dep = spec.dependencies.first
    assert_equal "bundler-unload", dep.name
    assert_kind_of Gem::Requirement, dep.requirement
    assert_kind_of Gem::Requirement, dep.instance_variable_get(:@version_requirements)
    assert_equal dep.requirement.requirements, [[">=", Gem::Version.new("1.0.2")]]

    # Empty fields should be nil
    assert_nil spec.autorequire
    assert_nil spec.post_install_message

    # Metadata should be empty hash
    assert_equal({}, spec.metadata)

    # specification_version should be Integer
    assert_kind_of Integer, spec.specification_version
    assert_equal 4, spec.specification_version
  end

  def test_empty_requirements_array
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test
      dependencies:
      - !ruby/object:Gem::Dependency
        name: foo
        requirement: !ruby/object:Gem::Requirement
          requirements:
        type: :runtime
        version_requirements: !ruby/object:Gem::Requirement
          requirements:
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "test", spec.name
    assert_equal 1, spec.dependencies.size

    dep = spec.dependencies.first
    assert_equal "foo", dep.name
    assert_kind_of Gem::Requirement, dep.requirement

    # Requirements should be empty array, not nil
    reqs = dep.requirement.instance_variable_get(:@requirements)
    assert_kind_of Array, reqs
    assert_equal [], reqs
  end

  def test_requirements_hash_converted_to_array
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Malformed YAML where requirements is a Hash instead of Array
    yaml = <<~YAML
      !ruby/object:Gem::Requirement
      requirements:
        foo: bar
    YAML

    req = Gem::YAMLSerializer.load(yaml, permitted_classes: ["Gem::Requirement"])
    assert_kind_of Gem::Requirement, req

    # Requirements should be converted from Hash to empty Array
    reqs = req.instance_variable_get(:@requirements)
    assert_kind_of Array, reqs
    assert_equal [], reqs

    # Should not raise error when used
    assert req.satisfied_by?(Gem::Version.new("1.0"))
  end

  def test_rdoc_options_hash_converted_to_array
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Some gemspecs incorrectly have rdoc_options: {} instead of rdoc_options: []
    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test-gem
      version: !ruby/object:Gem::Version
        version: 1.0.0
      rdoc_options: {}
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "test-gem", spec.name

    # rdoc_options should be converted from Hash to Array
    assert_kind_of Array, spec.rdoc_options
    assert_equal [], spec.rdoc_options
  end

  def test_load_returns_hash_for_comment_only_yaml
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Bundler config files may contain only comments after deleting all keys
    result = Gem::YAMLSerializer.load("---\n# BUNDLE_FOO: \"bar\"\n")
    assert_kind_of Hash, result
    assert_empty result
  end

  def test_load_returns_hash_for_empty_document
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    assert_equal({}, Gem::YAMLSerializer.load("---\n"))
    assert_equal({}, Gem::YAMLSerializer.load(""))
    assert_equal({}, Gem::YAMLSerializer.load(nil))
  end

  def test_load_returns_hash_for_flow_empty_hash
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Gem::YAMLSerializer.dump({}) produces "--- {}\n"
    result = Gem::YAMLSerializer.load("--- {}\n")
    assert_kind_of Hash, result
    assert_empty result
  end

  def test_load_parses_flow_empty_hash_as_value
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    result = Gem::YAMLSerializer.load("metadata: {}\n")
    assert_kind_of Hash, result
    assert_kind_of Hash, result["metadata"]
    assert_empty result["metadata"]
  end

  def test_yaml_non_specific_tag_stripped
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Legacy RubyGems (1.x) generated YAML with ! non-specific tags like:
    #   - ! '>='
    # The ! prefix should be ignored.
    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: legacy-gem
      version: !ruby/object:Gem::Version
        version: 0.1.0
      required_ruby_version: !ruby/object:Gem::Requirement
        none: false
        requirements:
        - - ! '>='
          - !ruby/object:Gem::Version
            version: '0'
      required_rubygems_version: !ruby/object:Gem::Requirement
        none: false
        requirements:
        - - ! '>='
          - !ruby/object:Gem::Version
            version: 1.3.5
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "legacy-gem", spec.name
    assert_equal Gem::Requirement.new(">= 0"), spec.required_ruby_version
    assert_equal Gem::Requirement.new(">= 1.3.5"), spec.required_rubygems_version
  end

  def test_legacy_gemspec_with_anchors_and_non_specific_tags
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = true

    # Real-world pattern from gems like vegas-0.1.11 that combine
    # YAML anchors/aliases with ! non-specific tags
    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: legacy-gem
      version: !ruby/object:Gem::Version
        version: 0.1.11
      dependencies:
      - !ruby/object:Gem::Dependency
        name: rack
        requirement: &id001 !ruby/object:Gem::Requirement
          none: false
          requirements:
          - - ! '>='
            - !ruby/object:Gem::Version
              version: 1.0.0
        type: :runtime
        prerelease: false
        version_requirements: *id001
      - !ruby/object:Gem::Dependency
        name: mocha
        requirement: &id002 !ruby/object:Gem::Requirement
          none: false
          requirements:
          - - ~>
            - !ruby/object:Gem::Version
              version: 0.9.8
        type: :development
        prerelease: false
        version_requirements: *id002
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "legacy-gem", spec.name

    assert_equal 2, spec.dependencies.size

    rack_dep = spec.dependencies.find {|d| d.name == "rack" }
    assert_kind_of Gem::Dependency, rack_dep
    assert_equal :runtime, rack_dep.type
    assert_equal Gem::Requirement.new(">= 1.0.0"), rack_dep.requirement

    mocha_dep = spec.dependencies.find {|d| d.name == "mocha" }
    assert_kind_of Gem::Dependency, mocha_dep
    assert_equal :development, mocha_dep.type
    assert_equal Gem::Requirement.new("~> 0.9.8"), mocha_dep.requirement
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_non_specific_tag_on_plain_value
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # ! tag on a bracketed value like rubyforge_project: ! '[none]'
    result = Gem::YAMLSerializer.load("key: ! '[none]'\n")
    assert_equal({ "key" => "[none]" }, result)
  end

  def test_dump_quotes_dollar_sign_values
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Values starting with $ should be quoted to preserve them as strings
    yaml = Gem::YAMLSerializer.dump({ "BUNDLE_FOO" => "$BUILD_DIR", "BUNDLE_BAR" => "baz" })
    assert_include yaml, 'BUNDLE_FOO: "$BUILD_DIR"'
    assert_include yaml, "BUNDLE_BAR: baz"

    # Round-trip: ensure the quoted value is parsed back correctly
    result = Gem::YAMLSerializer.load(yaml)
    assert_equal "$BUILD_DIR", result["BUNDLE_FOO"]
    assert_equal "baz", result["BUNDLE_BAR"]
  end

  def test_dump_quotes_special_characters
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Various special characters that should trigger quoting
    special_values = {
      "dollar" => "$HOME",
      "exclamation" => "!important",
      "ampersand" => "&anchor",
      "asterisk" => "*ref",
      "colon_prefix" => ":symbol",
      "at_sign" => "@mention",
      "percent" => "%encoded",
    }

    yaml = Gem::YAMLSerializer.dump(special_values)
    special_values.each do |key, value|
      assert_include yaml, "#{key}: #{value.inspect}", "Value #{value.inspect} for key #{key} should be quoted"
    end

    # Round-trip
    result = Gem::YAMLSerializer.load(yaml)
    special_values.each do |key, value|
      assert_equal value, result[key], "Round-trip failed for key #{key}"
    end
  end

  def test_load_ambiguous_value_with_colon
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # "invalid: yaml: hah" is ambiguous YAML - our parser treats it as
    # {"invalid" => "yaml: hah"}, but the value looks like a nested mapping.
    # config_file.rb's load_file should detect this and reject it.
    result = Gem::YAMLSerializer.load("invalid: yaml: hah")
    assert_kind_of Hash, result
    assert_equal "yaml: hah", result["invalid"]
  end

  def test_nested_anchor_in_array_item
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    # Ensure aliases are enabled for this test
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = true

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test-gem
      version: !ruby/object:Gem::Version
        version: 1.0.0
      dependencies:
      - !ruby/object:Gem::Dependency
        name: foo
        requirement: !ruby/object:Gem::Requirement
          requirements:
          - &id002
            - ">="
            - !ruby/object:Gem::Version
              version: "0"
        type: :runtime
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    assert_equal "test-gem", spec.name

    dep = spec.dependencies.first
    assert_kind_of Gem::Dependency, dep

    # Requirements should be parsed as nested arrays, not strings
    assert_kind_of Array, dep.requirement.requirements
    assert_equal 1, dep.requirement.requirements.size

    req_item = dep.requirement.requirements.first
    assert_kind_of Array, req_item
    assert_equal ">=", req_item[0]
    assert_kind_of Gem::Version, req_item[1]
    assert_equal "0", req_item[1].version
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_roundtrip_specification
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    spec = Gem::Specification.new do |s|
      s.name = "round-trip-test"
      s.version = "2.3.4"
      s.platform = "ruby"
      s.authors = ["Test Author"]
      s.summary = "A test gem for round-trip"
      s.description = "Longer description of the test gem"
      s.files = ["lib/foo.rb", "README.md"]
      s.require_paths = ["lib"]
      s.homepage = "https://example.com"
      s.licenses = ["MIT"]
      s.metadata = { "source_code_uri" => "https://example.com/src" }
      s.add_dependency "rake", ">= 1.0"
    end

    yaml = Gem::YAMLSerializer.dump(spec)
    loaded = Gem::SafeYAML.safe_load(yaml)

    assert_kind_of Gem::Specification, loaded
    assert_equal "round-trip-test", loaded.name
    assert_equal Gem::Version.new("2.3.4"), loaded.version
    assert_equal ["Test Author"], loaded.authors
    assert_equal "A test gem for round-trip", loaded.summary
    assert_equal ["README.md", "lib/foo.rb"], loaded.files
    assert_equal ["lib"], loaded.require_paths
    assert_equal "https://example.com", loaded.homepage
    assert_equal ["MIT"], loaded.licenses
    assert_equal({ "source_code_uri" => "https://example.com/src" }, loaded.metadata)
    assert_equal 1, loaded.dependencies.size

    dep = loaded.dependencies.first
    assert_equal "rake", dep.name
    assert_equal :runtime, dep.type
  end

  def test_roundtrip_version
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    ver = Gem::Version.new("1.2.3")
    yaml = Gem::YAMLSerializer.dump(ver)
    loaded = Gem::YAMLSerializer.load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Version, loaded
    assert_equal ver, loaded
  end

  def test_roundtrip_platform
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    plat = Gem::Platform.new("x86_64-linux")
    yaml = Gem::YAMLSerializer.dump(plat)
    loaded = Gem::YAMLSerializer.load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Platform, loaded
    assert_equal plat.cpu, loaded.cpu
    assert_equal plat.os, loaded.os
    assert_equal plat.version, loaded.version
  end

  def test_roundtrip_requirement
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    req = Gem::Requirement.new(">= 1.0", "< 2.0")
    yaml = Gem::YAMLSerializer.dump(req)
    loaded = Gem::YAMLSerializer.load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Requirement, loaded
    assert_equal req.requirements.sort_by(&:to_s), loaded.requirements.sort_by(&:to_s)
  end

  def test_roundtrip_dependency
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    dep = Gem::Dependency.new("foo", ">= 1.0", :development)
    yaml = Gem::YAMLSerializer.dump(dep)
    loaded = Gem::YAMLSerializer.load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Dependency, loaded
    assert_equal "foo", loaded.name
    assert_equal :development, loaded.type
    assert_equal dep.requirement.requirements, loaded.requirement.requirements
  end

  def test_roundtrip_nested_hash
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    obj = { "a" => { "b" => "c", "d" => [1, 2, 3] } }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    assert_equal obj, loaded
  end

  def test_roundtrip_block_scalar
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    obj = { "text" => "line1\nline2\n" }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    assert_equal "line1\nline2\n", loaded["text"]
  end

  def test_roundtrip_special_characters
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    obj = {
      "dollar" => "$HOME",
      "exclamation" => "!important",
      "ampersand" => "&anchor",
      "asterisk" => "*ref",
      "colon_prefix" => ":symbol",
      "hash_char" => "value#comment",
      "brackets" => "[item]",
      "braces" => "{key}",
      "comma" => "a,b,c",
    }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    obj.each do |key, value|
      assert_equal value, loaded[key], "Round-trip failed for key #{key}"
    end
  end

  def test_roundtrip_boolean_nil_integer
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    obj = { "flag" => true, "count" => 42, "empty" => nil, "off" => false }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    assert_equal true, loaded["flag"]
    assert_equal 42, loaded["count"]
    assert_nil loaded["empty"]
    assert_equal false, loaded["off"]
  end

  def test_roundtrip_time
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    time = Time.utc(2024, 6, 15, 12, 30, 45)
    obj = { "created" => time }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    assert_kind_of Time, loaded["created"]
    assert_equal time.year, loaded["created"].year
    assert_equal time.month, loaded["created"].month
    assert_equal time.day, loaded["created"].day
  end

  def test_roundtrip_empty_collections
    pend "YAMLSerializer is not loaded" unless defined?(Gem::YAMLSerializer)

    obj = { "arr" => [], "hash" => {} }
    yaml = Gem::YAMLSerializer.dump(obj)
    loaded = Gem::YAMLSerializer.load(yaml)

    assert_equal [], loaded["arr"]
    assert_equal({}, loaded["hash"])
  end
end
