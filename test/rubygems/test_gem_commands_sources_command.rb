require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/sources_command'

class TestGemCommandsSourcesCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::SourcesCommand.new
  end

  def test_execute
    util_setup_source_info_cache
    @cmd.handle_options []

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** CURRENT SOURCES ***

#{@gem_repo}
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add
    util_setup_fake_fetcher

    si = Gem::SourceIndex.new
    si.add_spec @a1

    @fetcher.data["http://beta-gems.example.com/Marshal.#{@marshal_version}"] =
      si.dump

    @cmd.handle_options %w[--add http://beta-gems.example.com]

    util_setup_source_info_cache

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Bulk updating Gem source index for: http://beta-gems.example.com/
http://beta-gems.example.com added to sources
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    Gem::SourceInfoCache.cache.flush
    assert_equal %W[http://beta-gems.example.com #{@gem_repo}],
                 Gem::SourceInfoCache.cache_data.keys.sort
  end

  def test_execute_add_nonexistent_source
    util_setup_fake_fetcher

    @fetcher.data["http://beta-gems.example.com/Marshal.#{@marshal_version}"] =
      proc do
        raise Gem::RemoteFetcher::FetchError, 'it died'
      end

    Gem::RemoteFetcher.instance_variable_set :@fetcher, @fetcher

    @cmd.handle_options %w[--add http://beta-gems.example.com]

    util_setup_source_info_cache

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Error fetching http://beta-gems.example.com:
\tit died
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add_bad_uri
    @cmd.handle_options %w[--add beta-gems.example.com]

    util_setup_source_info_cache

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
beta-gems.example.com is not a URI
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_clear_all
    @cmd.handle_options %w[--clear-all]

    util_setup_source_info_cache

    cache = Gem::SourceInfoCache.cache
    cache.update
    cache.write_cache

    assert File.exist?(cache.system_cache_file),
           'system cache file'
    assert File.exist?(cache.latest_system_cache_file),
           'latest system cache file'

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** Removed user source cache ***
*** Removed latest user source cache ***
*** Removed system source cache ***
*** Removed latest system source cache ***
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    assert !File.exist?(cache.system_cache_file),
           'system cache file'
    assert !File.exist?(cache.latest_system_cache_file),
           'latest system cache file'

  end

  def test_execute_remove
    @cmd.handle_options %W[--remove #{@gem_repo}]

    util_setup_source_info_cache

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    Gem::SourceInfoCache.cache.flush
    assert_equal [], Gem::SourceInfoCache.cache_data.keys
  end

  def test_execute_remove_no_network
    @cmd.handle_options %W[--remove #{@gem_repo}]

    util_setup_fake_fetcher

    @fetcher.data["#{@gem_repo}/Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    Gem::SourceInfoCache.cache.flush
    assert_equal [], Gem::SourceInfoCache.cache_data.keys
  end

  def test_execute_update
    @cmd.handle_options %w[--update]

    util_setup_source_info_cache
    Gem::SourceInfoCache.reset

    util_setup_fake_fetcher
    si = Gem::SourceIndex.new
    si.add_spec @a1
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = si.dump

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Bulk updating Gem source index for: #{@gem_repo}/
source cache successfully updated
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

end

