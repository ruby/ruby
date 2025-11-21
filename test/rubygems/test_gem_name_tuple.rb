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

  def test_spec_name
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "a-0.gemspec", n.spec_name
  end

  def test_spaceship
    a   = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform::RUBY
    a_p = Gem::NameTuple.new "a", Gem::Version.new(0), Gem::Platform.local

    assert_equal 1, a_p.<=>(a)
  end

  def test_deconstruct
    name_tuple = Gem::NameTuple.new "rails", Gem::Version.new("7.0.0"), "ruby"
    assert_equal ["rails", Gem::Version.new("7.0.0"), "ruby"], name_tuple.deconstruct
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
end
