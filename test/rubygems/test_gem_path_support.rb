# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems'
require 'fileutils'

class TestGemPathSupport < Gem::TestCase
  def setup
    super

    ENV["GEM_HOME"] = @tempdir
    ENV["GEM_PATH"] = [@tempdir, "something"].join(File::PATH_SEPARATOR)
  end

  def test_initialize
    ps = Gem::PathSupport.new

    assert_equal ENV["GEM_HOME"], ps.home

    expected = util_path
    assert_equal expected, ps.path, "defaults to GEM_PATH"
  end

  def test_initialize_home
    ps = Gem::PathSupport.new "GEM_HOME" => "#{@tempdir}/foo"

    assert_equal File.join(@tempdir, "foo"), ps.home

    expected = util_path + [File.join(@tempdir, 'foo')]
    assert_equal expected, ps.path
  end

  if defined?(File::ALT_SEPARATOR) and File::ALT_SEPARATOR
    def test_initialize_home_normalize
      alternate = @tempdir.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
      ps = Gem::PathSupport.new "GEM_HOME" => alternate

      assert_equal @tempdir, ps.home, "normalize values"
    end
  end

  def test_initialize_path
    ps = Gem::PathSupport.new "GEM_PATH" => %W[#{@tempdir}/foo #{@tempdir}/bar]

    assert_equal ENV["GEM_HOME"], ps.home

    expected = [
                File.join(@tempdir, 'foo'),
                File.join(@tempdir, 'bar'),
                ENV["GEM_HOME"],
               ]

    assert_equal expected, ps.path
  end

  def test_initialize_home_path
    ps = Gem::PathSupport.new("GEM_HOME" => "#{@tempdir}/foo",
                              "GEM_PATH" => %W[#{@tempdir}/foo #{@tempdir}/bar])

    assert_equal File.join(@tempdir, "foo"), ps.home

    expected = [File.join(@tempdir, 'foo'), File.join(@tempdir, 'bar')]
    assert_equal expected, ps.path
  end

  def util_path
    ENV["GEM_PATH"].split(File::PATH_SEPARATOR)
  end

  def test_initialize_spec
    ENV["GEM_SPEC_CACHE"] = nil

    ps = Gem::PathSupport.new
    assert_equal Gem.default_spec_cache_dir, ps.spec_cache_dir

    ENV["GEM_SPEC_CACHE"] = 'bar'

    ps = Gem::PathSupport.new
    assert_equal ENV["GEM_SPEC_CACHE"], ps.spec_cache_dir

    ENV["GEM_SPEC_CACHE"] = File.join @tempdir, 'spec_cache'

    ps = Gem::PathSupport.new "GEM_SPEC_CACHE" => "foo"
    assert_equal "foo", ps.spec_cache_dir
  end
end
