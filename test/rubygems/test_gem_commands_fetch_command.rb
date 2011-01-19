######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/package'
require 'rubygems/security'
require 'rubygems/commands/fetch_command'

class TestGemCommandsFetchCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::FetchCommand.new
  end

  def test_execute
    util_setup_fake_fetcher
    util_setup_spec_fetcher @a2

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      File.read(File.join(@gemhome, 'cache', @a2.file_name))

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, @a2.file_name)),
           "#{@a2.full_name} not fetched"
  end

  def test_execute_prerelease
    util_setup_fake_fetcher true
    util_setup_spec_fetcher @a2, @a2_pre

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      File.read(File.join(@gemhome, 'cache', @a2.file_name))
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      File.read(File.join(@gemhome, 'cache', @a2_pre.file_name))

    @cmd.options[:args] = [@a2.name]
    @cmd.options[:prerelease] = true

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, @a2_pre.file_name)),
           "#{@a2_pre.full_name} not fetched"
  end

  def test_execute_version
    util_setup_fake_fetcher
    util_setup_spec_fetcher @a1, @a2

    @fetcher.data["#{@gem_repo}gems/#{@a1.file_name}"] =
      File.read(File.join(@gemhome, 'cache', @a1.file_name))

    @cmd.options[:args] = [@a2.name]
    @cmd.options[:version] = Gem::Requirement.new '1'

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, @a1.file_name)),
           "#{@a1.full_name} not fetched"
  end

end

