# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/name_tuple'

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
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "ruby", n.platform

    n = Gem::NameTuple.new "a", Gem::Version.new(0), nil
    assert_equal "ruby", n.platform

    n = Gem::NameTuple.new "a", Gem::Version.new(0), ""
    assert_equal "ruby", n.platform
  end

  def test_spec_name
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "a-0.gemspec", n.spec_name
  end

  def test_spaceship
    a   = Gem::NameTuple.new 'a', Gem::Version.new(0), Gem::Platform::RUBY
    a_p = Gem::NameTuple.new 'a', Gem::Version.new(0), Gem::Platform.local

    assert_equal 1, a_p.<=>(a)
  end
end
