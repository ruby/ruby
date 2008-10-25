require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/source_info_cache_entry'

class TestGemSourceInfoCacheEntry < RubyGemTestCase

  def setup
    super

    util_setup_fake_fetcher

    @si = Gem::SourceIndex.new
    @si.add_spec @a1
    @sic_e = Gem::SourceInfoCacheEntry.new @si, @si.dump.size
  end

  def test_refresh
    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}.Z"] =
      proc { raise }
    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = @si.dump

    use_ui @ui do
      @sic_e.refresh @gem_repo, true
    end
  end

  def test_refresh_all
    @si.add_spec @a2

    a1_name = @a1.full_name
    a2_name = @a2.full_name

    @fetcher.data["#{@gem_repo}quick/index.rz"] =
        util_zip [a1_name, a2_name].join("\n")
    @fetcher.data["#{@gem_repo}quick/latest_index.rz"] = util_zip a2_name
    @fetcher.data["#{@gem_repo}quick/Marshal.#{Gem.marshal_version}/#{a1_name}.gemspec.rz"] = util_zip Marshal.dump(@a1)
    @fetcher.data["#{@gem_repo}quick/Marshal.#{Gem.marshal_version}/#{a2_name}.gemspec.rz"] = util_zip Marshal.dump(@a2)
    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] =
      Marshal.dump @si

    sic_e = Gem::SourceInfoCacheEntry.new Gem::SourceIndex.new, 0

    assert_equal [], sic_e.source_index.map { |n,| n }

    use_ui @ui do
      assert sic_e.refresh(@gem_repo, false)
    end

    assert_equal [a2_name], sic_e.source_index.map { |n,| n }.sort

    use_ui @ui do
      sic_e.refresh @gem_repo, true
    end

    assert_equal [a1_name, a2_name], sic_e.source_index.map { |n,| n }.sort
  end

  def test_refresh_bad_uri
    assert_raises URI::BadURIError do
      @sic_e.refresh 'gems.example.com', true
    end
  end

  def test_refresh_update
    si = Gem::SourceIndex.new
    si.add_spec @a1
    si.add_spec @b2
    @fetcher.data["#{@gem_repo}Marshal.#{@marshal_version}"] = si.dump

    use_ui @ui do
      @sic_e.refresh @gem_repo, true
    end

    new_gem = @sic_e.source_index.specification(@b2.full_name)
    assert_equal @b2.full_name, new_gem.full_name
  end

end

