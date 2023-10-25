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
end
