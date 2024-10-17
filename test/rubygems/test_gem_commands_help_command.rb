# frozen_string_literal: true

require "rubygems"
require_relative "helper"
require "rubygems/commands/help_command"
require "rubygems/package"
require "rubygems/command_manager"

class TestGemCommandsHelpCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::HelpCommand.new
  end

  def test_gem_help_bad
    util_gem "bad" do |out, err|
      assert_equal("", out)
      assert_match "Unknown command bad", err
    end
  end

  def test_gem_help_gem_dependencies
    util_gem "gem_dependencies" do |out, err|
      assert_match "gem.deps.rb", out
      assert_equal "", err
    end
  end

  def test_gem_help_platforms
    util_gem "platforms" do |out, err|
      assert_match(/x86-freebsd/, out)
      assert_equal "", err
    end
  end

  def test_gem_help_build
    util_gem "build" do |out, err|
      assert_match(/-C PATH *Run as if gem build was started in <PATH>/, out)
      assert_equal "", err
    end
  end

  def test_gem_help_commands
    mgr = Gem::CommandManager.new

    util_gem "commands" do |out, err|
      mgr.command_names.each do |cmd|
        unless mgr[cmd].deprecated?
          assert_match(/\s+#{cmd}\s+\S+/, out)
        end
      end

      if Gem::HAVE_OPENSSL
        assert_empty err

        refute_match(/No command found for /, out)
      end
    end
  end

  def test_gem_help_commands_omits_deprecated_commands
    mgr = Gem::CommandManager.new

    util_gem "commands" do |out, _err|
      deprecated_commands = mgr.command_names.select {|cmd| mgr[cmd].deprecated? }
      deprecated_commands.each do |cmd|
        refute_match(/\A\s+#{cmd}\s+\S+\z/, out)
      end
    end
  end

  def test_gem_no_args_shows_help
    util_gem do |out, err|
      assert_match(/Usage:/, out)
      assert_match(/gem install/, out)
      assert_equal "", err
    end
  end

  def util_gem(*args)
    @cmd.options[:args] = args

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    yield @ui.output, @ui.error
  end
end
