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
    ps = Gem::PathSupport.new ENV

    assert_equal ENV["GEM_HOME"], ps.home

    expected = util_path
    assert_equal expected, ps.path, "defaults to GEM_PATH"
  end

  def test_initialize_home
    ps = Gem::PathSupport.new ENV.to_hash.merge("GEM_HOME" => "#{@tempdir}/foo")

    assert_equal File.join(@tempdir, "foo"), ps.home

    expected = util_path + [File.join(@tempdir, 'foo')]
    assert_equal expected, ps.path
  end

  if File::ALT_SEPARATOR
    def test_initialize_home_normalize
      alternate = @tempdir.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
      ps = Gem::PathSupport.new "GEM_HOME" => alternate

      assert_equal @tempdir, ps.home, "normalize values"
    end
  end

  def test_initialize_path
    ps = Gem::PathSupport.new ENV.to_hash.merge("GEM_PATH" => %W[#{@tempdir}/foo #{@tempdir}/bar].join(Gem.path_separator))

    assert_equal ENV["GEM_HOME"], ps.home

    expected = [
      File.join(@tempdir, 'foo'),
      File.join(@tempdir, 'bar'),
      ENV["GEM_HOME"],
    ]

    assert_equal expected, ps.path
  end

  def test_initialize_regexp_path_separator
    Gem.stub(:path_separator, /#{File::PATH_SEPARATOR}/) do
      path = %W[#{@tempdir}/foo
                #{File::PATH_SEPARATOR}
                #{@tempdir}/bar
                #{File::PATH_SEPARATOR}].join
      ps = Gem::PathSupport.new "GEM_PATH" => path, "GEM_HOME" => ENV["GEM_HOME"]

      assert_equal ENV["GEM_HOME"], ps.home

      expected = [
        File.join(@tempdir, 'foo'),
        File.join(@tempdir, 'bar'),
      ] + Gem.default_path << ENV["GEM_HOME"]

      assert_equal expected, ps.path
    end
  end

  def test_initialize_path_with_defaults
    path = %W[#{@tempdir}/foo
              #{File::PATH_SEPARATOR}
              #{@tempdir}/bar
              #{File::PATH_SEPARATOR}].join
    ps = Gem::PathSupport.new "GEM_PATH" => path, "GEM_HOME" => ENV["GEM_HOME"]

    assert_equal ENV["GEM_HOME"], ps.home

    expected = [
      File.join(@tempdir, 'foo'),
      File.join(@tempdir, 'bar'),
    ] + Gem.default_path << ENV["GEM_HOME"]

    assert_equal expected, ps.path
  end

  def test_initialize_home_path
    ps = Gem::PathSupport.new("GEM_HOME" => "#{@tempdir}/foo",
                              "GEM_PATH" => %W[#{@tempdir}/foo #{@tempdir}/bar].join(Gem.path_separator))

    assert_equal File.join(@tempdir, "foo"), ps.home

    expected = [File.join(@tempdir, 'foo'), File.join(@tempdir, 'bar')]
    assert_equal expected, ps.path
  end

  def util_path
    ENV["GEM_PATH"].split(File::PATH_SEPARATOR)
  end

  def test_initialize_spec
    ENV["GEM_SPEC_CACHE"] = nil

    ps = Gem::PathSupport.new ENV
    assert_equal Gem.default_spec_cache_dir, ps.spec_cache_dir

    ENV["GEM_SPEC_CACHE"] = 'bar'

    ps = Gem::PathSupport.new ENV
    assert_equal ENV["GEM_SPEC_CACHE"], ps.spec_cache_dir

    ENV["GEM_SPEC_CACHE"] = File.join @tempdir, 'spec_cache'

    ps = Gem::PathSupport.new "GEM_SPEC_CACHE" => "foo"
    assert_equal "foo", ps.spec_cache_dir
  end

  def test_gem_paths_do_not_contain_symlinks
    dir = "#{@tempdir}/realgemdir"
    symlink = "#{@tempdir}/symdir"
    Dir.mkdir dir
    begin
      File.symlink(dir, symlink)
    rescue NotImplementedError, SystemCallError
      skip 'symlinks not supported'
    end
    not_existing = "#{@tempdir}/does_not_exist"
    path = "#{symlink}#{File::PATH_SEPARATOR}#{not_existing}"

    ps = Gem::PathSupport.new "GEM_PATH" => path, "GEM_HOME" => symlink
    assert_equal dir, ps.home
    assert_equal [dir, not_existing], ps.path
  end
end
