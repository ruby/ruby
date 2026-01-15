# frozen_string_literal: true

require_relative "helper"
require "rubygems/source"

class TestGemSourceSpecificFile < Gem::TestCase
  def setup
    super

    @a, @a_gem = util_gem "a", "1"
    @sf = Gem::Source::SpecificFile.new(@a_gem)
  end

  def test_path
    assert_equal @a_gem, @sf.path
  end

  def test_spec
    assert_equal @a, @sf.spec
  end

  def test_load_specs
    assert_equal [@a.name_tuple], @sf.load_specs
  end

  def test_fetch_spec
    assert_equal @a, @sf.fetch_spec(@a.name_tuple)
  end

  def test_fetch_spec_fails_on_unknown_name
    assert_raise Gem::Exception do
      @sf.fetch_spec(nil)
    end
  end

  def test_download
    assert_equal @a_gem, @sf.download(@a)
  end

  def test_spaceship
    a1 = quick_gem "a", "1"
    util_build_gem a1

    remote    = Gem::Source.new @gem_repo
    specific  = Gem::Source::SpecificFile.new a1.cache_file
    installed = Gem::Source::Installed.new
    local     = Gem::Source::Local.new

    assert_equal(0, specific.<=>(specific), "specific <=> specific") # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands

    assert_equal(-1, remote.<=>(specific), "remote <=> specific")
    assert_equal(1, specific.<=>(remote), "specific <=> remote")

    assert_equal(-1, specific.<=>(local),     "specific <=> local")
    assert_equal(1, local.    <=>(specific),  "local <=> specific")

    assert_equal(-1, specific. <=>(installed), "specific <=> installed")
    assert_equal(1, installed.<=>(specific), "installed <=> specific")

    a2 = quick_gem "a", "2"
    util_build_gem a2

    b1 = quick_gem "b", "1"
    util_build_gem b1

    a1_source = specific
    a2_source = Gem::Source::SpecificFile.new a2.cache_file
    b1_source = Gem::Source::SpecificFile.new b1.cache_file

    assert_nil       a1_source.<=>(b1_source), "a1_source <=> b1_source"

    assert_equal(-1, a1_source.<=>(a2_source), "a1_source <=> a2_source")
    assert_equal(0, a1_source.<=>(a1_source), "a1_source <=> a1_source") # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
    assert_equal(1, a2_source.<=>(a1_source), "a2_source <=> a1_source")
  end

  def test_pretty_print
    assert_equal "#<Gem::Source::SpecificFile[SpecificFile: #{@sf.path}]>", @sf.pretty_inspect.gsub(/\s+/, " ").strip
  end
end
