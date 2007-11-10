#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/source_info_cache'

class Gem::SourceIndex
  public :gems
end

class TestGemSourceInfoCache < RubyGemTestCase

  def setup
    @original_sources = Gem.sources

    super

    util_setup_fake_fetcher

    @sic = Gem::SourceInfoCache.new
    @sic.instance_variable_set :@fetcher, @fetcher

    prep_cache_files @sic
  end

  def teardown
    super
    Gem.sources.replace @original_sources
  end

  def test_self_cache_refreshes
    Gem.configuration.update_sources = true #true by default
    source_index = Gem::SourceIndex.new 'key' => 'sys'
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = source_index.dump

    Gem.sources.replace %W[#{@gem_repo}]

    use_ui @ui do
      assert_not_nil Gem::SourceInfoCache.cache
      assert_kind_of Gem::SourceInfoCache, Gem::SourceInfoCache.cache
      assert_equal Gem::SourceInfoCache.cache.object_id,
                   Gem::SourceInfoCache.cache.object_id
      assert_match %r|Bulk updating|, @ui.output
    end
  end

  def test_self_cache_skips_refresh_based_on_configuration
    Gem.configuration.update_sources = false
    source_index = Gem::SourceIndex.new 'key' => 'sys'
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = source_index.dump

    Gem.sources.replace %w[#{@gem_repo}]

    use_ui @ui do
      assert_not_nil Gem::SourceInfoCache.cache
      assert_kind_of Gem::SourceInfoCache, Gem::SourceInfoCache.cache
      assert_equal Gem::SourceInfoCache.cache.object_id,
                   Gem::SourceInfoCache.cache.object_id
      assert_no_match %r|Bulk updating|, @ui.output
    end
  end

  def test_self_cache_data
    source_index = Gem::SourceIndex.new 'key' => 'sys'
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = source_index.dump

    Gem::SourceInfoCache.instance_variable_set :@cache, nil
    sice = Gem::SourceInfoCacheEntry.new source_index, 0

    use_ui @ui do
      assert_equal source_index.gems,
                   Gem::SourceInfoCache.cache_data[@gem_repo].source_index.gems
    end
  end

  def test_cache_data
    assert_equal [['key','sys']], @sic.cache_data.to_a.sort
  end

  def test_cache_data_dirty
    def @sic.dirty() @dirty; end
    assert_equal false, @sic.dirty, 'clean on init'
    @sic.cache_data
    assert_equal false, @sic.dirty, 'clean on fetch'
    @sic.update
    @sic.cache_data
    assert_equal true, @sic.dirty, 'still dirty'
  end

  def test_cache_data_irreparable
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = @source_index.dump

    data = { @gem_repo => { 'totally' => 'borked' } }

    [@sic.system_cache_file, @sic.user_cache_file].each do |fn|
      FileUtils.mkdir_p File.dirname(fn)
      open(fn, "wb") { |f| f.write Marshal.dump(data) }
    end

    @sic.instance_eval { @cache_data = nil }

    fetched = use_ui @ui do @sic.cache_data end

    fetched_si = fetched["#{@gem_repo}"].source_index

    assert_equal @source_index.index_signature, fetched_si.index_signature
  end

  def test_cache_data_none_readable
    FileUtils.chmod 0222, @sic.system_cache_file
    FileUtils.chmod 0222, @sic.user_cache_file
    return if (File.stat(@sic.system_cache_file).mode & 0222) != 0222
    return if (File.stat(@sic.user_cache_file).mode & 0222) != 0222
    # HACK for systems that don't support chmod
    assert_equal({}, @sic.cache_data)
  end

  def test_cache_data_none_writable
    FileUtils.chmod 0444, @sic.system_cache_file
    FileUtils.chmod 0444, @sic.user_cache_file
    e = assert_raise RuntimeError do
      @sic.cache_data
    end
    assert_equal 'unable to locate a writable cache file', e.message
  end

  def test_cache_data_repair
    data = {
        @gem_repo => {
          'cache' => Gem::SourceIndex.new,
          'size' => 0,
      }
    }
    [@sic.system_cache_file, @sic.user_cache_file].each do |fn|
      FileUtils.mkdir_p File.dirname(fn)
      open(fn, "wb") { |f| f.write Marshal.dump(data) }
    end

    @sic.instance_eval { @cache_data = nil }

    expected = {
        @gem_repo =>
          Gem::SourceInfoCacheEntry.new(Gem::SourceIndex.new, 0)
    }
    assert_equal expected, @sic.cache_data
  end

  def test_cache_data_user_fallback
    FileUtils.chmod 0444, @sic.system_cache_file
    assert_equal [['key','usr']], @sic.cache_data.to_a.sort
  end

  def test_cache_file
    assert_equal @gemcache, @sic.cache_file
  end

  def test_cache_file_user_fallback
    FileUtils.chmod 0444, @sic.system_cache_file
    assert_equal @usrcache, @sic.cache_file
  end

  def test_cache_file_none_writable
    FileUtils.chmod 0444, @sic.system_cache_file
    FileUtils.chmod 0444, @sic.user_cache_file
    e = assert_raise RuntimeError do
      @sic.cache_file
    end
    assert_equal 'unable to locate a writable cache file', e.message
  end

  def test_flush
    @sic.cache_data['key'] = 'new'
    @sic.update
    @sic.flush

    assert_equal [['key','new']], read_cache(@sic.system_cache_file).to_a.sort
  end

  def test_read_system_cache
    assert_equal [['key','sys']], @sic.cache_data.to_a.sort
  end

  def test_read_user_cache
    FileUtils.chmod 0444, @sic.system_cache_file

    assert_equal [['key','usr']], @sic.cache_data.to_a.sort
  end

  def test_search
    si = Gem::SourceIndex.new @gem1.full_name => @gem1
    cache_data = {
      @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil)
    }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [@gem1], @sic.search(//)
  end

  def test_search_dependency
    si = Gem::SourceIndex.new @gem1.full_name => @gem1
    cache_data = {
      @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil)
    }
    @sic.instance_variable_set :@cache_data, cache_data

    dep = Gem::Dependency.new @gem1.name, @gem1.version

    assert_equal [@gem1], @sic.search(dep)
  end

  def test_search_no_matches
    si = Gem::SourceIndex.new @gem1.full_name => @gem1
    cache_data = {
      @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil)
    }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [], @sic.search(/nonexistent/)
  end

  def test_search_no_matches_in_source
    si = Gem::SourceIndex.new @gem1.full_name => @gem1
    cache_data = {
      @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil)
    }
    @sic.instance_variable_set :@cache_data, cache_data
    Gem.sources.replace %w[more-gems.example.com]

    assert_equal [], @sic.search(/nonexistent/)
  end

  def test_search_with_source
    si = Gem::SourceIndex.new @gem1.full_name => @gem1
    cache_data = {
      @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil)
    }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [[@gem1, @gem_repo]],
                 @sic.search_with_source(//)
  end

  def test_system_cache_file
    assert_equal File.join(Gem.dir, "source_cache"), @sic.system_cache_file
  end

  def test_user_cache_file
    assert_equal @usrcache, @sic.user_cache_file
  end

  def test_write_cache
    @sic.cache_data['key'] = 'new'
    @sic.write_cache

    assert_equal [['key', 'new']],
                 read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [['key', 'usr']],
                 read_cache(@sic.user_cache_file).to_a.sort
  end

  def test_write_cache_user
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({'key' => 'new'})
    @sic.update
    @sic.write_cache

    assert_equal [['key', 'sys']], read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [['key', 'new']], read_cache(@sic.user_cache_file).to_a.sort
  end

  def test_write_cache_user_from_scratch
    FileUtils.rm_rf @sic.user_cache_file
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({'key' => 'new'})
    @sic.update
    @sic.write_cache

    assert_equal [['key', 'sys']], read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [['key', 'new']], read_cache(@sic.user_cache_file).to_a.sort
  end

  def test_write_cache_user_no_directory
    FileUtils.rm_rf File.dirname(@sic.user_cache_file)
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({'key' => 'new'})
    @sic.update
    @sic.write_cache

    assert_equal [['key','sys']], read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [['key','new']], read_cache(@sic.user_cache_file).to_a.sort
  end

end

