# frozen_string_literal: true
require_relative "helper"
require "rubygems/source"

require "fileutils"

class TestGemSourceLocal < Gem::TestCase
  def setup
    super

    @sl = Gem::Source::Local.new

    @a, @a_gem = util_gem "a", "1"
    @ap, @ap_gem = util_gem "a", "2.a"
    @b, @b_gem = util_gem "b", "1"

    FileUtils.mv @a_gem, @tempdir
    FileUtils.mv @ap_gem, @tempdir
    FileUtils.mv @b_gem, @tempdir
  end

  def test_load_specs_released
    assert_equal [@a.name_tuple, @b.name_tuple].sort,
                 @sl.load_specs(:released).sort
  end

  def test_load_specs_prerelease
    assert_equal [@ap.name_tuple], @sl.load_specs(:prerelease)
  end

  def test_load_specs_latest
    a2, a2_gem = util_gem "a", "2"

    FileUtils.mv a2_gem, @tempdir

    assert_equal [a2.name_tuple, @b.name_tuple].sort,
                 @sl.load_specs(:latest).sort
  end

  def test_find_gem
    assert_equal "a-1", @sl.find_gem("a").full_name
  end

  def test_find_gem_highest_version
    _, a2_gem = util_gem "a", "2"
    FileUtils.mv a2_gem, @tempdir

    assert_equal "a-2", @sl.find_gem("a").full_name
  end

  def test_find_gem_specific_version
    _, a2_gem = util_gem "a", "2"
    FileUtils.mv a2_gem, @tempdir

    req = Gem::Requirement.create("= 1")

    assert_equal "a-1", @sl.find_gem("a", req).full_name
  end

  def test_find_gem_prerelease
    req = Gem::Requirement.create(">= 0")
    assert_equal "a-2.a", @sl.find_gem("a", req, true).full_name
  end

  def test_fetch_spec
    s = @sl.fetch_spec @a.name_tuple
    assert_equal s, @a
  end

  def test_inspect
    assert_equal '#<Gem::Source::Local specs: "NOT LOADED">', @sl.inspect

    @sl.load_specs :released

    inner = [@a, @ap, @b].map {|t| t.name_tuple }.inspect

    assert_equal "#<Gem::Source::Local specs: #{inner}>", @sl.inspect
  end

  def test_download
    path = @sl.download @a

    assert_equal File.expand_path(@a.file_name), path
  end

  def test_spaceship
    a1 = quick_gem "a", "1"
    util_build_gem a1

    remote    = Gem::Source.new @gem_repo
    specific  = Gem::Source::SpecificFile.new a1.cache_file
    installed = Gem::Source::Installed.new
    local     = Gem::Source::Local.new

    assert_equal(0, local.<=>(local), "local <=> local")

    assert_equal(-1, remote.<=>(local), "remote <=> local")
    assert_equal(1, local.<=>(remote), "local <=> remote")

    assert_equal(1, installed.<=>(local), "installed <=> local")
    assert_equal(-1, local.<=>(installed), "local <=> installed")

    assert_equal(-1, specific.<=>(local), "specific <=> local")
    assert_equal(1, local.<=>(specific), "local <=> specific")
  end
end
