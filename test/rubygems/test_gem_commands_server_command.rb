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

  def test_handle_options_port
    @cmd.send :handle_options, %w[-p 0]
    assert_equal 0, @cmd.options[:port]

    @cmd.send :handle_options, %w[-p 65535]
    assert_equal 65535, @cmd.options[:port]

    @cmd.send :handle_options, %w[-p http]
    assert_equal 80, @cmd.options[:port]

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.send :handle_options, %w[-p nonexistent]
    end

    assert_equal 'invalid argument: -p nonexistent: no such named service',
                 e.message

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.send :handle_options, %w[-p 65536]
    end

    assert_equal 'invalid argument: -p 65536: not a port number',
                 e.message
  end

end

