require "rubygems"
require "rubygems/test_case"
require "rubygems/commands/help_command"
require "rubygems/package"
require "rubygems/command_manager"
require File.expand_path('../rubygems_plugin', __FILE__)

class TestGemCommandsHelpCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::HelpCommand.new

    load File.expand_path('../rubygems_plugin.rb', __FILE__) unless
      Gem::Commands.const_defined? :InterruptCommand
  end

  def test_gem_help_bad
    util_gem 'bad' do |out, err|
      assert_equal('', out)
      assert_match "Unknown command bad", err
    end
  end

  def test_gem_help_platforms
    util_gem 'platforms' do |out, err|
      assert_match(/x86-freebsd/, out)
      assert_equal '', err
    end
  end

  def test_gem_help_commands
    mgr = Gem::CommandManager.new

    util_gem 'commands' do |out, err|
      mgr.command_names.each do |cmd|
        assert_match(/\s+#{cmd}\s+\S+/, out)
      end

      if defined?(OpenSSL::SSL) then
        assert_empty err

        refute_match 'No command found for ', out
      end
    end
  end

  def test_gem_no_args_shows_help
    util_gem do |out, err|
      assert_match(/Usage:/, out)
      assert_match(/gem install/, out)
      assert_equal '', err
    end
  end

  def util_gem *args
    @cmd.options[:args] = args

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    yield @ui.output, @ui.error
  end
end
