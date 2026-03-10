# frozen_string_literal: true

require_relative "helper"

Gem.load_yaml

class TestGemSafeYAML < Gem::TestCase
  def yaml_load(input, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES,
                permitted_symbols: Gem::SafeYAML::PERMITTED_SYMBOLS,
                aliases: true)
    if Gem.use_psych?
      Psych.safe_load(input, permitted_classes: permitted_classes,
                             permitted_symbols: permitted_symbols,
                             aliases: aliases)
    else
      Gem::YAMLSerializer.load(input, permitted_classes: permitted_classes,
                                      permitted_symbols: permitted_symbols,
                                      aliases: aliases)
    end
  end

  def yaml_dump(obj)
    if Gem.use_psych?
      obj.to_yaml
    else
      Gem::YAMLSerializer.dump(obj)
    end
  end

  def test_aliases_enabled_by_default
    assert_predicate Gem::SafeYAML, :aliases_enabled?
    assert_equal({ "a" => "a", "b" => "a" }, Gem::SafeYAML.safe_load("a: &a a\nb: *a\n"))
  end

  def test_aliases_disabled
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

    yaml = <<~YAML
      --- !ruby/object:SomeDisallowedClass
      foo: bar
    YAML

    exception = assert_raise(Psych::DisallowedClass) do
      Gem::SafeYAML.safe_load(yaml)
    end
    assert_match(/unspecified class/, exception.message)
  end

  def test_disallowed_symbol_rejected

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

    exception = assert_raise(Psych::DisallowedClass) do
      Gem::SafeYAML.safe_load(yaml)
    end
    assert_match(/unspecified class/, exception.message)
  end

  def test_yaml_serializer_aliases_disabled

    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = false
    refute_predicate Gem::SafeYAML, :aliases_enabled?

    yaml = "a: &anchor value\nb: *anchor\n"

    assert_raise(Psych::AliasesNotEnabled) do
      Gem::SafeYAML.safe_load(yaml)
    end
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_real_gemspec_fileutils

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

    reqs = dep.requirement.instance_variable_get(:@requirements)
    if Gem.use_psych?
      # Psych sets nil for empty value
      assert_nil reqs
    else
      # YAMLSerializer normalizes empty requirements to []
      assert_kind_of Array, reqs
      assert_equal [], reqs
    end
  end

  def test_requirements_hash_converted_to_array

    # Malformed YAML where requirements is a Hash instead of Array
    yaml = <<~YAML
      !ruby/object:Gem::Requirement
      requirements:
        foo: bar
    YAML

    req = yaml_load(yaml, permitted_classes: ["Gem::Requirement"])
    assert_kind_of Gem::Requirement, req

    reqs = req.instance_variable_get(:@requirements)
    if Gem.use_psych?
      # Psych assigns the Hash directly
      assert_kind_of Hash, reqs
    else
      # YAMLSerializer normalizes Hash to empty Array
      assert_kind_of Array, reqs
      assert_equal [], reqs
      assert req.satisfied_by?(Gem::Version.new("1.0"))
    end
  end

  def test_rdoc_options_hash_converted_to_array

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

    if Gem.use_psych?
      # Psych assigns the empty Hash directly
      assert_kind_of Hash, spec.rdoc_options
    else
      # YAMLSerializer normalizes Hash to Array
      assert_kind_of Array, spec.rdoc_options
      assert_equal [], spec.rdoc_options
    end
  end

  def test_load_returns_nil_for_comment_only_yaml

    # Bundler config files may contain only comments after deleting all keys
    result = yaml_load("---\n# BUNDLE_FOO: \"bar\"\n")
    assert_nil result
  end

  def test_load_returns_nil_for_empty_document

    assert_nil yaml_load("---\n")
    assert_nil yaml_load("")
    assert_raise(TypeError) { yaml_load(nil) }
  end

  def test_load_returns_hash_for_flow_empty_hash

    # yaml_dump({}) produces "--- {}\n"
    result = yaml_load("--- {}\n")
    assert_kind_of Hash, result
    assert_empty result
  end

  def test_load_parses_flow_empty_hash_as_value

    result = yaml_load("metadata: {}\n")
    assert_kind_of Hash, result
    assert_kind_of Hash, result["metadata"]
    assert_empty result["metadata"]
  end

  def test_yaml_non_specific_tag_stripped

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

    # ! tag on a bracketed value like rubyforge_project: ! '[none]'
    result = yaml_load("key: ! '[none]'\n")
    assert_equal({ "key" => "[none]" }, result)
  end

  def test_dump_quotes_dollar_sign_values

    # Values starting with $ should be quoted to preserve them as strings
    yaml = yaml_dump({ "BUNDLE_FOO" => "$BUILD_DIR", "BUNDLE_BAR" => "baz" })
    assert_include yaml, 'BUNDLE_FOO: "$BUILD_DIR"'
    assert_include yaml, "BUNDLE_BAR: baz"

    # Round-trip: ensure the quoted value is parsed back correctly
    result = yaml_load(yaml)
    assert_equal "$BUILD_DIR", result["BUNDLE_FOO"]
    assert_equal "baz", result["BUNDLE_BAR"]
  end

  def test_dump_quotes_special_characters

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

    yaml = yaml_dump(special_values)
    special_values.each do |key, value|
      assert_include yaml, "#{key}: #{value.inspect}", "Value #{value.inspect} for key #{key} should be quoted"
    end

    # Round-trip
    result = yaml_load(yaml)
    special_values.each do |key, value|
      assert_equal value, result[key], "Round-trip failed for key #{key}"
    end
  end

  def test_load_ambiguous_value_with_colon

    # "invalid: yaml: hah" is ambiguous YAML - our parser treats it as
    # {"invalid" => "yaml: hah"}, but the value looks like a nested mapping.
    # config_file.rb's load_file should detect this and reject it.
    if Gem.use_psych?
      # Psych raises a syntax error for this ambiguous YAML
      assert_raise(Psych::SyntaxError) do
        yaml_load("invalid: yaml: hah")
      end
    else
      result = yaml_load("invalid: yaml: hah")
      assert_kind_of Hash, result
      assert_equal "yaml: hah", result["invalid"]
    end
  end

  def test_nested_anchor_in_array_item

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

    yaml = yaml_dump(spec)
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

    ver = Gem::Version.new("1.2.3")
    yaml = yaml_dump(ver)
    loaded = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Version, loaded
    assert_equal ver, loaded
  end

  def test_roundtrip_platform

    plat = Gem::Platform.new("x86_64-linux")
    yaml = yaml_dump(plat)
    loaded = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Platform, loaded
    assert_equal plat.cpu, loaded.cpu
    assert_equal plat.os, loaded.os
    assert_equal plat.version, loaded.version
  end

  def test_roundtrip_requirement

    req = Gem::Requirement.new(">= 1.0", "< 2.0")
    yaml = yaml_dump(req)
    loaded = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Requirement, loaded
    assert_equal req.requirements.sort_by(&:to_s), loaded.requirements.sort_by(&:to_s)
  end

  def test_roundtrip_dependency

    dep = Gem::Dependency.new("foo", ">= 1.0", :development)
    yaml = yaml_dump(dep)
    loaded = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)

    assert_kind_of Gem::Dependency, loaded
    assert_equal "foo", loaded.name
    assert_equal :development, loaded.type
    assert_equal dep.requirement.requirements, loaded.requirement.requirements
  end

  def test_roundtrip_nested_hash

    obj = { "a" => { "b" => "c", "d" => [1, 2, 3] } }
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    assert_equal obj, loaded
  end

  def test_roundtrip_block_scalar

    obj = { "text" => "line1\nline2\n" }
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    assert_equal "line1\nline2\n", loaded["text"]
  end

  def test_roundtrip_special_characters

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
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    obj.each do |key, value|
      assert_equal value, loaded[key], "Round-trip failed for key #{key}"
    end
  end

  def test_roundtrip_boolean_nil_integer

    obj = { "flag" => true, "count" => 42, "empty" => nil, "off" => false }
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    assert_equal true, loaded["flag"]
    assert_equal 42, loaded["count"]
    assert_nil loaded["empty"]
    assert_equal false, loaded["off"]
  end

  def test_roundtrip_time

    time = Time.utc(2024, 6, 15, 12, 30, 45)
    obj = { "created" => time }
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    assert_kind_of Time, loaded["created"]
    assert_equal time.year, loaded["created"].year
    assert_equal time.month, loaded["created"].month
    assert_equal time.day, loaded["created"].day
  end

  def test_roundtrip_empty_collections

    obj = { "arr" => [], "hash" => {} }
    yaml = yaml_dump(obj)
    loaded = yaml_load(yaml)

    assert_equal [], loaded["arr"]
    assert_equal({}, loaded["hash"])
  end

  def test_load_double_quoted_escape_sequences

    result = yaml_load("newline: \"hello\\nworld\"")
    assert_equal "hello\nworld", result["newline"]

    result = yaml_load("tab: \"col1\\tcol2\"")
    assert_equal "col1\tcol2", result["tab"]

    result = yaml_load("cr: \"line\\rend\"")
    assert_equal "line\rend", result["cr"]

    result = yaml_load("quote: \"say\\\"hi\\\"\"")
    assert_equal "say\"hi\"", result["quote"]
  end

  def test_load_double_quoted_backslash_before_escape_chars

    # \\r in YAML should become literal backslash + r, not carriage return
    result = yaml_load('path: "D:\\\\ruby-mswin\\\\lib"')
    assert_equal "D:\\ruby-mswin\\lib", result["path"]

    # \\n should become literal backslash + n, not newline
    result = yaml_load('path: "C:\\\\new_folder"')
    assert_equal "C:\\new_folder", result["path"]

    # \\t should become literal backslash + t, not tab
    result = yaml_load('path: "C:\\\\tmp\\\\test"')
    assert_equal "C:\\tmp\\test", result["path"]

    # \\\\ should become two literal backslashes
    result = yaml_load('val: "a\\\\\\\\b"')
    assert_equal "a\\\\b", result["val"]
  end

  def test_load_single_quoted_escape

    result = yaml_load("key: 'it''s'")
    assert_equal "it's", result["key"]

    result = yaml_load("key: 'no escape \\n here'")
    assert_equal "no escape \\n here", result["key"]
  end

  def test_load_quoted_numeric_stays_string

    result = yaml_load("key: \"42\"")
    assert_equal "42", result["key"]
    assert_kind_of String, result["key"]

    result = yaml_load("key: '99'")
    assert_equal "99", result["key"]
    assert_kind_of String, result["key"]
  end

  def test_load_empty_string_value

    result = yaml_load("key: \"\"")
    assert_equal "", result["key"]
  end

  def test_load_unquoted_integer

    result = yaml_load("key: 42")
    assert_equal 42, result["key"]
    assert_kind_of Integer, result["key"]

    result = yaml_load("key: -7")
    assert_equal(-7, result["key"])
  end

  def test_load_boolean_values

    result = yaml_load("a: true\nb: false")
    assert_equal true, result["a"]
    assert_equal false, result["b"]
  end

  def test_load_nil_value

    # YAML 1.2: "nil" is not a null value, only ~ and null are
    result = yaml_load("key: nil")
    assert_equal "nil", result["key"]

    result = yaml_load("key: ~")
    assert_nil result["key"]

    result = yaml_load("key: null")
    assert_nil result["key"]
  end

  def test_load_time_value

    result = yaml_load("date: 2024-06-15 12:30:45.000000000 Z")
    assert_kind_of Time, result["date"]
    assert_equal 2024, result["date"].year
    assert_equal 6, result["date"].month
    assert_equal 15, result["date"].day
  end

  def test_load_block_scalar_keep_trailing_newline

    yaml = "text: |\n  line1\n  line2\n"
    result = yaml_load(yaml)
    assert_equal "line1\nline2\n", result["text"]
  end

  def test_load_block_scalar_strip_trailing_newline

    yaml = "text: |-\n  no trailing newline\n"
    result = yaml_load(yaml)
    assert_equal "no trailing newline", result["text"]
    refute result["text"].end_with?("\n")
  end

  def test_load_flow_array

    result = yaml_load("items: [a, b, c]")
    assert_equal ["a", "b", "c"], result["items"]
  end

  def test_load_flow_empty_array

    result = yaml_load("items: []")
    assert_equal [], result["items"]
  end

  def test_load_mapping_key_with_no_value

    result = yaml_load("key:")
    assert_kind_of Hash, result
    assert_nil result["key"]
  end

  def test_load_sequence_item_as_mapping

    yaml = "items:\n- name: foo\n  ver: 1\n- name: bar\n  ver: 2"
    result = yaml_load(yaml)
    assert_equal [{ "name" => "foo", "ver" => 1 }, { "name" => "bar", "ver" => 2 }], result["items"]
  end

  def test_load_nested_sequence

    yaml = "matrix:\n- - a\n  - b\n- - c\n  - d"
    result = yaml_load(yaml)
    assert_equal [["a", "b"], ["c", "d"]], result["matrix"]
  end

  def test_load_comment_stripped_from_value

    result = yaml_load("key: value # this is a comment")
    assert_equal "value", result["key"]
  end

  def test_load_comment_in_quoted_string_preserved

    result = yaml_load("key: \"value # not a comment\"")
    assert_equal "value # not a comment", result["key"]

    result = yaml_load("key: 'value # not a comment'")
    assert_equal "value # not a comment", result["key"]
  end

  def test_load_crlf_line_endings

    result = yaml_load("key: value\r\nother: data\r\n")
    assert_equal "value", result["key"]
    assert_equal "data", result["other"]
  end

  def test_load_version_requirement_old_tag

    yaml = <<~YAML
      !ruby/object:Gem::Version::Requirement
      requirements:
      - - ">="
        - !ruby/object:Gem::Version
          version: "1.0"
    YAML

    req = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)
    assert_kind_of Gem::Requirement, req
    assert_equal [[">=", Gem::Version.new("1.0")]], req.requirements
  end

  def test_load_platform_from_value_field

    yaml = "!ruby/object:Gem::Platform\nvalue: x86-linux\n"
    plat = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)
    assert_kind_of Gem::Platform, plat
    if Gem.use_psych?
      # Psych doesn't interpret the "value" field specially
      assert_nil plat.cpu
    else
      # YAMLSerializer parses the "value" field as a platform string
      assert_equal "x86", plat.cpu
      assert_equal "linux", plat.os
    end
  end

  def test_load_platform_from_cpu_os_version_fields

    yaml = "!ruby/object:Gem::Platform\ncpu: x86_64\nos: darwin\nversion: nil\n"
    plat = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)
    assert_kind_of Gem::Platform, plat
    assert_equal "x86_64", plat.cpu
    assert_equal "darwin", plat.os
  end

  def test_load_dependency_missing_requirement_uses_default

    yaml = <<~YAML
      !ruby/object:Gem::Dependency
      name: foo
      type: :runtime
    YAML

    dep = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)
    assert_kind_of Gem::Dependency, dep
    assert_equal "foo", dep.name
    assert_equal :runtime, dep.type
    if Gem.use_psych?
      # Psych doesn't set a default requirement
      assert_nil dep.instance_variable_get(:@requirement)
    else
      # YAMLSerializer sets a default Gem::Requirement
      assert_kind_of Gem::Requirement, dep.requirement
    end
  end

  def test_load_dependency_missing_type_defaults_to_runtime

    yaml = <<~YAML
      !ruby/object:Gem::Dependency
      name: bar
      requirement: !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: '0'
    YAML

    dep = yaml_load(yaml, permitted_classes: Gem::SafeYAML::PERMITTED_CLASSES)
    assert_equal :runtime, dep.type
  end

  def test_specification_version_non_numeric_string_not_converted

    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test
      version: !ruby/object:Gem::Version
        version: 1.0.0
      specification_version: abc
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Specification, spec
    # Non-numeric string should not be converted to Integer
    assert_equal "abc", spec.specification_version
  end

  def test_unknown_permitted_tag_raises_argument_error

    yaml = "!ruby/object:MyCustomClass\nfoo: bar\n"
    assert_raise(ArgumentError) do
      yaml_load(yaml, permitted_classes: ["MyCustomClass"])
    end
  end

  def test_dump_block_scalar_with_trailing_newline

    yaml = yaml_dump({ "text" => "line1\nline2\n" })
    assert_include yaml, " |\n"
    refute_includes yaml, " |-\n"
  end

  def test_dump_block_scalar_without_trailing_newline

    yaml = yaml_dump({ "text" => "line1\nline2" })
    assert_include yaml, " |-\n"
  end

  def test_dump_nil_value

    yaml = yaml_dump({ "key" => nil })

    loaded = yaml_load(yaml)
    assert_nil loaded["key"]
  end

  def test_dump_symbol_keys_quoted

    yaml = yaml_dump({ foo: "bar" })
    # Symbol keys should use inspect format
    assert_include yaml, ":foo:"

    # Symbol values in hash with symbol keys should be quoted
    yaml = yaml_dump({ type: ":runtime" })
    assert_include yaml, "\":runtime\""
  end

  def test_regression_flow_empty_hash_as_root

    # Previously returned Mapping struct instead of Hash
    result = yaml_load("--- {}")
    assert_kind_of Hash, result
    assert_empty result
  end

  def test_regression_alias_check_in_builder_not_parser

    # Previously aliases were resolved in Parser, bypassing Builder's policy check.
    # The Builder must enforce aliases: false.
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = false

    # Alias in mapping value
    assert_raise(Psych::AliasesNotEnabled) do
      yaml_load("a: &x val\nb: *x", aliases: false)
    end

    # Alias in sequence item
    assert_raise(Psych::AliasesNotEnabled) do
      yaml_load("items:\n- &x val\n- *x", aliases: false)
    end
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_regression_anchored_mapping_stored_for_alias_resolution

    # Previously build_mapping didn't call store_anchor, so anchored
    # Gem types (Requirement, etc.) couldn't be resolved via aliases.
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = true

    yaml = <<~YAML
      a: &req !ruby/object:Gem::Requirement
        requirements:
        - - ">="
          - !ruby/object:Gem::Version
            version: '0'
      b: *req
    YAML

    result = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Gem::Requirement, result["a"]
    assert_kind_of Gem::Requirement, result["b"]
    assert_equal result["a"].requirements, result["b"].requirements
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_regression_register_anchor_sets_node_anchor

    # Previously register_anchor only stored node in @anchors hash but
    # didn't set node.anchor, so Builder couldn't track anchored values.
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = true

    yaml = <<~YAML
      items:
      - &item !ruby/object:Gem::Version
        version: '1.0'
      - *item
    YAML

    result = Gem::SafeYAML.safe_load(yaml)
    assert_kind_of Array, result["items"]
    assert_equal 2, result["items"].size
    assert_kind_of Gem::Version, result["items"][0]
    assert_kind_of Gem::Version, result["items"][1]
    assert_equal result["items"][0], result["items"][1]
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end

  def test_regression_coerce_empty_hash_not_wrapped_in_scalar

    # Previously coerce("{}") returned Mapping but parse_plain_scalar
    # wrapped it in Scalar.new(value: Mapping), causing type mismatch.
    result = yaml_load("--- {}")
    assert_kind_of Hash, result

    result = yaml_load("key: {}")
    assert_kind_of Hash, result["key"]
  end

  def test_regression_rdoc_options_normalized_to_array

    # rdoc_options as Hash (malformed gemspec)
    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test
      version: !ruby/object:Gem::Version
        version: 1.0.0
      rdoc_options:
        --title: MyGem
        --main: README
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    if Gem.use_psych?
      # Psych assigns the Hash directly
      assert_kind_of Hash, spec.rdoc_options
    else
      # YAMLSerializer normalizes Hash rdoc_options to Array
      assert_kind_of Array, spec.rdoc_options
      assert_include spec.rdoc_options, "MyGem"
      assert_include spec.rdoc_options, "README"
    end
  end

  def test_regression_requirements_field_normalized_to_array

    # The "requirements" field in a Specification (not Requirement)
    # should be normalized from Hash to Array if malformed
    yaml = <<~YAML
      --- !ruby/object:Gem::Specification
      name: test
      version: !ruby/object:Gem::Version
        version: 1.0.0
      requirements:
        foo: bar
    YAML

    spec = Gem::SafeYAML.safe_load(yaml)
    if Gem.use_psych?
      # Psych assigns the Hash directly
      assert_kind_of Hash, spec.requirements
    else
      # YAMLSerializer normalizes Hash to Array
      assert_kind_of Array, spec.requirements
    end
  end
end
