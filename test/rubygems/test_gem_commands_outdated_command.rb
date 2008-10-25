require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/outdated_command'

class TestGemCommandsOutdatedCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::OutdatedCommand.new
  end

  def test_initialize
    assert @cmd.handles?(%W[--platform #{Gem::Platform.local}])
  end

  def test_execute
    local_01 = quick_gem 'foo', '0.1'
    local_02 = quick_gem 'foo', '0.2'
    remote_10 = quick_gem 'foo', '1.0'
    remote_20 = quick_gem 'foo', '2.0'

    remote_spec_file = File.join @gemhome, 'specifications',
                                 remote_10.full_name + ".gemspec"
    FileUtils.rm remote_spec_file

    remote_spec_file = File.join @gemhome, 'specifications',
                                 remote_20.full_name + ".gemspec"
    FileUtils.rm remote_spec_file

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher remote_10, remote_20

    use_ui @ui do @cmd.execute end

    assert_equal "foo (0.2 < 2.0)\n", @ui.output
    assert_equal "", @ui.error
  end

end

