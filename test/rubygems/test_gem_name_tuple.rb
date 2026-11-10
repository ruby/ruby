# frozen_string_literal: true

require_relative "helper"
require "rubygems/name_tuple"

class TestGemNameTuple < Gem::TestCase
  def test_full_name
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "a-0", n.full_name

    n = Gem::NameTuple.new "a", Gem::Version.new(0), nil
    assert_equal "a-0", n.full_name

    n = Gem::NameTuple.new "a", Gem::Version.new(0), ""
    assert_equal "a-0", n.full_name

    n = Gem::NameTuple.new "a", Gem::Version.new(0), "other"
    assert_equal "a-0-other", n.full_name
  end

  def test_platform_normalization
    a = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    b = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform::RUBY
    assert_equal a, b
    assert_equal a.hash, b.hash

    a = Gem::NameTuple.new "a", Gem::Version.new(0), nil
    b = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.new("ruby")
    assert_equal a, b
    assert_equal a.hash, b.hash

    a = Gem::NameTuple.new "a", Gem::Version.new(0), ""
    b = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.new("ruby")
    assert_equal a, b
    assert_equal a.hash, b.hash

    a = Gem::NameTuple.new "a", Gem::Version.new(0), "universal-darwin-23"
    b = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.new("universal-darwin-23")
    assert_equal a, b
    assert_equal a.hash, b.hash

    # Gem::Platform does normalization so that these are equal (note the missing dash before 21)
    a = Gem::NameTuple.new "a", Gem::Version.new(0), "universal-darwin-21"
    b = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.new("universal-darwin21")
    assert_equal a, b
    assert_equal a.hash, b.hash
  end

  def test_content_addressable_metadata
    n = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"

    assert_equal "abcdef12", n.content_address
    assert_equal "3.3", n.ruby_abi
    assert_equal "a-1-abcdef12", n.full_name
  end

  def test_to_a_includes_content_addressable_metadata
    tuple = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"

    assert_equal 5, tuple.to_a.length
    assert_equal ["a", Gem::Version.new(1), "x86_64-linux", "abcdef12", "3.3"], tuple.to_a
  end

  def test_to_a_excludes_nil_content_addressable_metadata
    tuple = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux"

    assert_equal 3, tuple.to_a.length
    assert_equal ["a", Gem::Version.new(1), "x86_64-linux"], tuple.to_a
  end

  def test_to_basic_excludes_content_addressable_metadata
    tuples = [
      Gem::NameTuple.new("a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"),
      Gem::NameTuple.new("b", Gem::Version.new(2), "ruby"),
    ]

    basic = Gem::NameTuple.to_basic tuples

    assert_equal [["a", Gem::Version.new(1), "x86_64-linux"],
                  ["b", Gem::Version.new(2), "ruby"]], basic
    basic.each {|row| assert_equal 3, row.length }
  end

  def test_from_list_serialized_form_omits_content_addressable_metadata
    serialized = Gem::NameTuple.from_list([["a", Gem::Version.new(1), "x86_64-linux"]]).first
    assert_equal "a", serialized.name
    assert_equal Gem::Version.new(1), serialized.version
    assert_equal "x86_64-linux", serialized.platform
    assert_nil serialized.content_address
    assert_nil serialized.ruby_abi
  end

  def test_from_list_full_form_preserves_content_addressable_metadata
    full = Gem::NameTuple.from_list([["a", Gem::Version.new(1), "x86_64-linux", "abcdef12", "3.3"]]).first
    assert_equal "a", full.name
    assert_equal Gem::Version.new(1), full.version
    assert_equal "x86_64-linux", full.platform
    assert_equal "abcdef12", full.content_address
    assert_equal "3.3", full.ruby_abi
  end

  def test_from_list_passes_name_tuple_objects_through
    original = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"
    rebuilt = Gem::NameTuple.from_list([original]).first
    assert_equal original, rebuilt
    assert_equal "abcdef12", rebuilt.content_address
    assert_equal "3.3", rebuilt.ruby_abi
  end

  def test_from_list_raises_for_invalid_array_length
    error = assert_raise(ArgumentError) do
      Gem::NameTuple.from_list([["a", Gem::Version.new(1)]])
    end
    assert_match "Expected a 3- or 5-element tuple, got 2", error.message
  end

  def test_from_list_raises_for_non_array_input
    error = assert_raise(ArgumentError) do
      Gem::NameTuple.from_list(["not an array"])
    end
    assert_match "Expected a Gem::NameTuple or Array, got String", error.message
  end

  def test_non_content_addressable_tuple_does_not_store_nil_content_addressable_metadata_ivars
    n = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux"

    refute_includes n.instance_variables, :@content_address
    refute_includes n.instance_variables, :@ruby_abi
    assert_nil n.content_address
    assert_nil n.ruby_abi
  end

  def test_sort_mixed_non_content_addressable_and_content_addressable_tuples
    non_content_addressable = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux"
    content_addressable = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"

    assert_equal [non_content_addressable, content_addressable], [content_addressable, non_content_addressable].sort
  end

  def test_spec_name
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "a-0.gemspec", n.spec_name
  end

  def test_content_addressable_spec_name
    n = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"

    assert_equal "a-1-abcdef12.gemspec", n.spec_name
  end

  def test_spaceship
    a   = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform::RUBY
    a_p = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.local

    assert_equal 1, a_p.<=>(a)
  end

  def test_deconstruct
    name_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "ruby"
    assert_equal ["rails", Gem::Version.new("7.0.0"), "ruby"], name_tuple.deconstruct

    ca_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"
    assert_equal ["rails", Gem::Version.new("7.0.0"), "x86_64-linux", "abcdef12", "3.3"], ca_tuple.deconstruct
  end

  def test_deconstruct_keys
    name_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "x86_64-linux"
    keys = name_tuple.deconstruct_keys(nil)
    assert_equal "rails", keys[:name]
    assert_equal Gem::Version.new("7.0.0"), keys[:version]
    assert_equal "x86_64-linux", keys[:platform]
  end

  def test_pattern_matching_array
    name_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "ruby"
    result =
      case name_tuple
      in [name, version, "ruby"]
        "#{name}-#{version}"
      else
        "no match"
      end
    assert_equal "rails-7.0.0", result
  end

  def test_pattern_matching_hash
    name_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "ruby"
    result =
      case name_tuple
      in name: "rails", version:, platform: "ruby"
        version.to_s
      else
        "no match"
      end
    assert_equal "7.0.0", result
  end

  def test_hash_distinguishes_content_addressable_variants
    base = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux"
    ca1 = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"
    ca2 = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "deadbeef", ruby_abi: "3.3"

    assert_equal [ca1.name, ca1.version, ca1.platform, ca1.content_address, ca1.ruby_abi].hash, ca1.hash
    refute_equal base.hash, ca1.hash
    refute_equal ca1.hash, ca2.hash
  end

  def test_array_equality_backward_compatible_for_non_content_addressable
    tuple = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux"

    assert_equal tuple, ["a", Gem::Version.new(1), "x86_64-linux"]
  end

  def test_array_equality_requires_full_form_for_content_addressable
    tuple = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"

    refute_equal tuple, ["a", Gem::Version.new(1), "x86_64-linux"]
    assert_equal tuple, ["a", Gem::Version.new(1), "x86_64-linux", "abcdef12", "3.3"]
  end

  def test_content_addressable_tuples_with_different_addresses_are_distinct
    first = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "abcdef12", ruby_abi: "3.3"
    second = Gem::NameTuple.new "a", Gem::Version.new(1), "x86_64-linux", content_address: "12345678", ruby_abi: "3.4"

    refute_equal first, second
    refute_equal first.hash, second.hash
  end
end
