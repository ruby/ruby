require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/server_command'

class TestGemCommandsServerCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::ServerCommand.new
  end

  def test_handle_options
    @cmd.send :handle_options, %w[-p 8808 --no-daemon]

    assert_equal false, @cmd.options[:daemon]
    assert_equal @gemhome, @cmd.options[:gemdir]
    assert_equal 8808, @cmd.options[:port]

    @cmd.send :handle_options, %w[-p 9999 -d /nonexistent --daemon]

    assert_equal true, @cmd.options[:daemon]
    assert_equal File.expand_path('/nonexistent'), @cmd.options[:gemdir]
    assert_equal 9999, @cmd.options[:port]
  end
end

