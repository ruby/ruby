# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/package'
require 'rubygems/security'
require 'rubygems/commands/fetch_command'

class TestGemCommandsFetchCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::FetchCommand.new
  end

  def test_execute
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    refute_path_exists File.join(@tempdir, 'cache'), 'sanity check'

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    a2 = specs['a-2']

    assert_path_exists(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
    refute_path_exists File.join(@tempdir, 'cache'),
                       'gem repository directories must not be created'
  end

  def test_execute_latest
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
    end

    refute_path_exists File.join(@tempdir, 'cache'), 'sanity check'

    @cmd.options[:args] = %w[a]
    @cmd.options[:version] = req('>= 0.1')

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    a2 = specs['a-2']
    assert_path_exists(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
    refute_path_exists File.join(@tempdir, 'cache'),
                       'gem repository directories must not be created'
  end

  def test_execute_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'a', '2.a'
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    a2 = specs['a-2']

    assert_path_exists(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
  end

  def test_execute_specific_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'a', '2.a'
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true
    @cmd.options[:version] = "2.a"

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    a2_pre = specs['a-2.a']

    assert_path_exists(File.join(@tempdir, a2_pre.file_name),
                       "#{a2_pre.full_name} not fetched")
  end

  def test_execute_version
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:version] = Gem::Requirement.new '1'

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    a1 = specs['a-1']

    assert_path_exists(File.join(@tempdir, a1.file_name),
                       "#{a1.full_name} not fetched")
  end

end

