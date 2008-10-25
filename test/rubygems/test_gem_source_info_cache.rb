#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

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

    @si_new = Gem::SourceIndex.new
    @sice_new = Gem::SourceInfoCacheEntry.new @si_new, 0

    prep_cache_files @sic

    @sic.reset_cache_data
  end

  def teardown
    super
    Gem.sources.replace @original_sources
    Gem::SourceInfoCache.instance_variable_set :@cache, nil
  end

  def test_self_cache_refreshes
    Gem.configuration.update_sources = true #true by default
    si = Gem::SourceIndex.new
    si.add_spec @a1

    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = si.dump

    Gem.sources.replace %W[#{@gem_repo}]

    use_ui @ui do
      refute_nil Gem::SourceInfoCache.cache
      assert_kind_of Gem::SourceInfoCache, Gem::SourceInfoCache.cache
      assert_equal Gem::SourceInfoCache.cache.object_id,
                   Gem::SourceInfoCache.cache.object_id
    end

    assert_match %r|Bulk updating|, @ui.output
  end

  def test_self_cache_skips_refresh_based_on_configuration
    Gem.configuration.update_sources = false
    si = Gem::SourceIndex.new
    si.add_spec @a1

    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = si.dump

    Gem.sources.replace %w[#{@gem_repo}]

    use_ui @ui do
      refute_nil Gem::SourceInfoCache.cache
      assert_kind_of Gem::SourceInfoCache, Gem::SourceInfoCache.cache
      assert_equal Gem::SourceInfoCache.cache.object_id,
                   Gem::SourceInfoCache.cache.object_id
      refute_match %r|Bulk updating|, @ui.output
    end
  end

  def test_self_cache_data
    si = Gem::SourceIndex.new
    si.add_spec @a1

    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = si.dump

    Gem::SourceInfoCache.instance_variable_set :@cache, nil
    sice = Gem::SourceInfoCacheEntry.new si, 0

    use_ui @ui do
      gems = Gem::SourceInfoCache.cache_data[@gem_repo].source_index.gems
      gem_names = gems.map { |_, spec| spec.full_name }

      assert_equal si.gems.map { |_,spec| spec.full_name }, gem_names
    end
  end

  def test_cache_data
    assert_equal [[@gem_repo, @usr_sice]], @sic.cache_data.to_a.sort
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
    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = @source_index.dump

    data = { @gem_repo => { 'totally' => 'borked' } }

    cache_files = [
      @sic.system_cache_file,
      @sic.latest_system_cache_file,
      @sic.user_cache_file,
      @sic.latest_user_cache_file
    ]

    cache_files.each do |fn|
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
    FileUtils.chmod 0222, @sic.latest_system_cache_file
    FileUtils.chmod 0222, @sic.user_cache_file
    FileUtils.chmod 0222, @sic.latest_user_cache_file
    return if (File.stat(@sic.system_cache_file).mode & 0222) != 0222
    return if (File.stat(@sic.user_cache_file).mode & 0222) != 0222
    # HACK for systems that don't support chmod
    assert_equal({}, @sic.cache_data)
  end

  def test_cache_data_none_writable
    FileUtils.chmod 0444, @sic.system_cache_file
    FileUtils.chmod 0444, @sic.user_cache_file
    e = assert_raises RuntimeError do
      @sic.cache_data
    end
    assert_equal 'unable to locate a writable cache file', e.message
  end

  def test_cache_data_nonexistent
    FileUtils.rm @sic.system_cache_file
    FileUtils.rm @sic.latest_system_cache_file
    FileUtils.rm @sic.user_cache_file
    FileUtils.rm @sic.latest_user_cache_file

    # TODO test verbose output
    assert_equal [], @sic.cache_data.to_a.sort
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

    assert_equal [[@gem_repo, @usr_sice]], @sic.cache_data.to_a.sort
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
    e = assert_raises RuntimeError do
      @sic.cache_file
    end
    assert_equal 'unable to locate a writable cache file', e.message
  end

  def test_flush
    @sic.cache_data[@gem_repo] = @sice_new
    @sic.update
    @sic.flush

    assert_equal [[@gem_repo, @sice_new]],
                 read_cache(@sic.system_cache_file).to_a.sort
  end

  def test_latest_cache_data
    util_make_gems

    sice = Gem::SourceInfoCacheEntry.new @source_index, 0

    @sic.set_cache_data @gem_repo => sice
    latest = @sic.latest_cache_data
    beginning_with_a = Gem::Dependency.new(/^a/, Gem::Requirement.default)
    gems = latest[@gem_repo].source_index.search(beginning_with_a).map { |s| s.full_name }

    assert_equal %w[a-2 a_evil-9], gems
  end

  def test_latest_cache_file
    latest_cache_file = File.join File.dirname(@gemcache),
                                  "latest_#{File.basename @gemcache}"
    assert_equal latest_cache_file, @sic.latest_cache_file
  end

  def test_latest_system_cache_file
    assert_equal File.join(Gem.dir, "latest_source_cache"),
                 @sic.latest_system_cache_file
  end

  def test_latest_user_cache_file
    assert_equal @latest_usrcache, @sic.latest_user_cache_file
  end

  def test_read_system_cache
    assert_equal [[@gem_repo, @sys_sice]], @sic.cache_data.to_a.sort
  end

  def test_read_user_cache
    FileUtils.chmod 0444, @sic.user_cache_file
    FileUtils.chmod 0444, @sic.latest_user_cache_file

    @si = Gem::SourceIndex.new
    @si.add_specs @a1, @a2

    @sice = Gem::SourceInfoCacheEntry.new @si, 0

    @sic.set_cache_data({ @gem_repo => @sice })
    @sic.update
    @sic.write_cache
    @sic.reset_cache_data

    user_cache_data = @sic.cache_data.to_a.sort

    assert_equal 1, user_cache_data.length
    user_cache_data = user_cache_data.first

    assert_equal @gem_repo, user_cache_data.first

    gems = user_cache_data.last.source_index.map { |_,spec| spec.full_name }
    assert_equal [@a2.full_name], gems
  end

  def test_search
    si = Gem::SourceIndex.new
    si.add_spec @a1
    cache_data = { @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil) }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [@a1], @sic.search(//)
  end

  def test_search_all
    util_make_gems

    sice = Gem::SourceInfoCacheEntry.new @source_index, 0

    @sic.set_cache_data @gem_repo => sice
    @sic.update
    @sic.instance_variable_set :@only_latest, false
    @sic.write_cache
    @sic.reset_cache_data

    gem_names = @sic.search(//, false, true).map { |spec| spec.full_name }

    assert_equal %w[a-1 a-2 a_evil-9 c-1.2], gem_names
  end

  def test_search_dependency
    si = Gem::SourceIndex.new
    si.add_spec @a1
    cache_data = { @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil) }
    @sic.instance_variable_set :@cache_data, cache_data

    dep = Gem::Dependency.new @a1.name, @a1.version

    assert_equal [@a1], @sic.search(dep)
  end

  def test_search_no_matches
    si = Gem::SourceIndex.new
    si.add_spec @a1
    cache_data = { @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil) }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [], @sic.search(/nonexistent/)
  end

  def test_search_no_matches_in_source
    si = Gem::SourceIndex.new
    si.add_spec @a1
    cache_data = { @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil) }
    @sic.instance_variable_set :@cache_data, cache_data
    Gem.sources.replace %w[more-gems.example.com]

    assert_equal [], @sic.search(/nonexistent/)
  end

  def test_search_with_source
    si = Gem::SourceIndex.new
    si.add_spec @a1
    cache_data = { @gem_repo => Gem::SourceInfoCacheEntry.new(si, nil) }
    @sic.instance_variable_set :@cache_data, cache_data

    assert_equal [[@a1, @gem_repo]],
                 @sic.search_with_source(//)
  end

  def test_system_cache_file
    assert_equal File.join(Gem.dir, "source_cache"), @sic.system_cache_file
  end

  def test_user_cache_file
    assert_equal @usrcache, @sic.user_cache_file
  end

  def test_write_cache
    @sic.cache_data[@gem_repo] = @sice_new
    @sic.write_cache

    assert_equal [[@gem_repo, @sice_new]],
                 read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [[@gem_repo, @usr_sice]],
                 read_cache(@sic.user_cache_file).to_a.sort
  end

  def test_write_cache_user
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({@gem_repo => @sice_new})
    @sic.update
    @sic.write_cache
    @sic.instance_variable_set :@only_latest, false

    assert File.exist?(@sic.user_cache_file), 'user_cache_file'
    assert File.exist?(@sic.latest_user_cache_file),
           'latest_user_cache_file exists'

    assert_equal [[@gem_repo, @sys_sice]],
                 read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [[@gem_repo, @sice_new]],
                 read_cache(@sic.user_cache_file).to_a.sort
  end

  def test_write_cache_user_from_scratch
    FileUtils.rm_rf @sic.user_cache_file
    FileUtils.rm_rf @sic.latest_user_cache_file

    FileUtils.chmod 0444, @sic.system_cache_file
    FileUtils.chmod 0444, @sic.latest_system_cache_file

    @si = Gem::SourceIndex.new
    @si.add_specs @a1, @a2

    @sice = Gem::SourceInfoCacheEntry.new @si, 0

    @sic.set_cache_data({ @gem_repo => @sice })
    @sic.update

    @sic.write_cache

    assert File.exist?(@sic.user_cache_file), 'system_cache_file'
    assert File.exist?(@sic.latest_user_cache_file),
           'latest_system_cache_file'

    user_cache_data = read_cache(@sic.user_cache_file).to_a.sort
    assert_equal 1, user_cache_data.length, 'user_cache_data length'
    user_cache_data = user_cache_data.first

    assert_equal @gem_repo, user_cache_data.first

    gems = user_cache_data.last.source_index.map { |_,spec| spec.full_name }
    assert_equal [@a1.full_name, @a2.full_name], gems.sort

    user_cache_data = read_cache(@sic.latest_user_cache_file).to_a.sort
    assert_equal 1, user_cache_data.length
    user_cache_data = user_cache_data.first

    assert_equal @gem_repo, user_cache_data.first

    gems = user_cache_data.last.source_index.map { |_,spec| spec.full_name }
    assert_equal [@a2.full_name], gems
  end

  def test_write_cache_user_no_directory
    FileUtils.rm_rf File.dirname(@sic.user_cache_file)
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({ @gem_repo => @sice_new })
    @sic.update
    @sic.write_cache

    assert_equal [[@gem_repo, @sys_sice]],
                 read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [[@gem_repo, @sys_sice]],
                 read_cache(@sic.user_cache_file).to_a.sort
    assert_equal [[@gem_repo, @sice_new]],
                 read_cache(@sic.latest_user_cache_file).to_a.sort
  end

  def test_write_cache_user_only_latest
    FileUtils.chmod 0444, @sic.system_cache_file
    @sic.set_cache_data({@gem_repo => @sice_new})
    @sic.update
    @sic.write_cache

    assert File.exist?(@sic.user_cache_file), 'user_cache_file'
    assert File.exist?(@sic.latest_user_cache_file),
           'latest_user_cache_file exists'

    assert_equal [[@gem_repo, @sys_sice]],
                 read_cache(@sic.system_cache_file).to_a.sort
    assert_equal [[@gem_repo, @sice_new]],
                 read_cache(@sic.user_cache_file).to_a.sort
  end

end

