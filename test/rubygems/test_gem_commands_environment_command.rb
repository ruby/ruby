# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/environment_command"

class TestGemCommandsEnvironmentCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::EnvironmentCommand.new
  end

  def test_execute
    orig_sources = Gem.sources.dup
    orig_path = ENV["PATH"]
    ENV["PATH"] = %w[/usr/local/bin /usr/bin /bin].join(File::PATH_SEPARATOR)
    Gem.sources.replace %w[http://gems.example.com]
    Gem.configuration["gemcutter_key"] = "blah"

    @cmd.send :handle_options, %w[]

    use_ui @ui do
      @cmd.execute
    end

    assert_match(/RUBYGEMS VERSION: (\d\.)+\d/, @ui.output)
    assert_match(/RUBY VERSION: \d+\.\d+\.\d+ \(.*\) \[.*\]/, @ui.output)
    assert_match(/INSTALLATION DIRECTORY: #{Regexp.escape @gemhome}/,
                 @ui.output)
    assert_match(/USER INSTALLATION DIRECTORY: #{Regexp.escape Gem.user_dir}/,
                 @ui.output)
    assert_match(/RUBYGEMS PREFIX: /, @ui.output)
    assert_match(/RUBY EXECUTABLE:.*#{RbConfig::CONFIG['ruby_install_name']}/,
                 @ui.output)
    assert_match(/GIT EXECUTABLE: #{@cmd.send(:git_path)}/, @ui.output)
    assert_match(/SYSTEM CONFIGURATION DIRECTORY:/, @ui.output)
    assert_match(/EXECUTABLE DIRECTORY:/, @ui.output)
    assert_match(/RUBYGEMS PLATFORMS:/, @ui.output)
    assert_match(/- #{Gem::Platform.local}/, @ui.output)
    assert_match(/GEM PATHS:/, @ui.output)
    assert_match(/- #{Regexp.escape @gemhome}/, @ui.output)
    assert_match(/GEM CONFIGURATION:/, @ui.output)
    assert_match(/"gemcutter_key" => "\*\*\*\*"/, @ui.output)
    assert_match(/:verbose => /, @ui.output)
    assert_match(/REMOTE SOURCES:/, @ui.output)

    assert_match(/- SHELL PATH:/, @ui.output)
    assert_match %r{- /usr/local/bin$}, @ui.output
    assert_match %r{- /usr/bin$},       @ui.output
    assert_match %r{- /bin$},           @ui.output

    assert_empty @ui.error
  ensure
    Gem.sources.replace orig_sources
    ENV["PATH"] = orig_path
  end

  def test_execute_gemdir
    @cmd.send :handle_options, %w[gemdir]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{@gemhome}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_user_gemdir
    @cmd.send :handle_options, %w[user_gemdir]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{Gem.user_dir}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_user_gemhome
    @cmd.send :handle_options, %w[user_gemhome]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{Gem.user_dir}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_gempath
    @cmd.send :handle_options, %w[gempath]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{@gemhome}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_gempath_multiple
    Gem.clear_paths
    path = [@gemhome, "#{@gemhome}2"].join File::PATH_SEPARATOR
    ENV["GEM_PATH"] = path

    @cmd.send :handle_options, %w[gempath]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{Gem.path.join File::PATH_SEPARATOR}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_remotesources
    orig_sources = Gem.sources.dup
    Gem.sources.replace %w[http://gems.example.com]

    @cmd.send :handle_options, %w[remotesources]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "http://gems.example.com\n", @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.sources.replace orig_sources
  end

  def test_execute_unknown
    @cmd.send :handle_options, %w[unknown]

    assert_raise Gem::CommandLineError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_version
    @cmd.send :handle_options, %w[version]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{Gem::VERSION}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_platform
    @cmd.send :handle_options, %w[platform]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{Gem.platforms.join File::PATH_SEPARATOR}\n", @ui.output
    assert_equal "", @ui.error
  end
end
