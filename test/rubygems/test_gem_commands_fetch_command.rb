require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
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

    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] =
      @source_index.dump
    @fetcher.data["#{@gem_repo}/gems/#{@a2.full_name}.gem"] =
      File.read(File.join(@gemhome, 'cache', "#{@a2.full_name}.gem"))

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, "#{@a2.full_name}.gem"))
  end

end

