# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/source'

class TestGemSourceVendor < Gem::TestCase
  def test_initialize
    source = Gem::Source::Vendor.new 'vendor/foo'

    assert_equal 'vendor/foo', source.uri
  end

  def test_spaceship
    vendor    = Gem::Source::Vendor.new 'vendor/foo'
    remote    = Gem::Source.new @gem_repo
    git       = Gem::Source::Git.new 'a', 'a', 'master'
    installed = Gem::Source::Installed.new

    assert_equal(0, vendor.<=>(vendor),    'vendor <=> vendor')

    assert_equal(1, vendor.<=>(remote),    'vendor <=> remote')
    assert_equal(-1, remote.<=>(vendor), 'remote <=> vendor')

    assert_equal(1, vendor.<=>(git), 'vendor <=> git')
    assert_equal(-1, git.<=>(vendor), 'git <=> vendor')

    assert_equal(1, vendor.<=>(installed), 'vendor <=> installed')
    assert_equal(-1, installed.<=>(vendor), 'installed <=> vendor')
  end
end
