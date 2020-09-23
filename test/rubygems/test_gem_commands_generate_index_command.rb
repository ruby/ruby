# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/indexer'
require 'rubygems/commands/generate_index_command'

class TestGemCommandsGenerateIndexCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::GenerateIndexCommand.new
    @cmd.options[:directory] = @gemhome
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    specs = File.join @gemhome, "specs.4.8.gz"

    assert File.exist?(specs), specs
  end

  def test_execute_no_modern
    @cmd.options[:modern] = false

    use_ui @ui do
      @cmd.execute
    end

    specs = File.join @gemhome, "specs.4.8.gz"

    assert File.exist?(specs), specs
  end

  def test_handle_options_directory
    return if win_platform?
    refute_equal '/nonexistent', @cmd.options[:directory]

    @cmd.handle_options %w[--directory /nonexistent]

    assert_equal '/nonexistent', @cmd.options[:directory]
  end

  def test_handle_options_directory_windows
    return unless win_platform?

    refute_equal '/nonexistent', @cmd.options[:directory]

    @cmd.handle_options %w[--directory C:/nonexistent]

    assert_equal 'C:/nonexistent', @cmd.options[:directory]
  end

  def test_handle_options_update
    @cmd.handle_options %w[--update]

    assert @cmd.options[:update]
  end

  def test_handle_options_modern
    use_ui @ui do
      @cmd.handle_options %w[--modern]
    end

    assert_equal \
      "WARNING:  The \"--modern\" option has been deprecated and will be removed in Rubygems 4.0. Modern indexes (specs, latest_specs, and prerelease_specs) are always generated, so this option is not needed.\n",
      @ui.error
  end

  def test_handle_options_no_modern
    use_ui @ui do
      @cmd.handle_options %w[--no-modern]
    end

    assert_equal \
      "WARNING:  The \"--no-modern\" option has been deprecated and will be removed in Rubygems 4.0. The `--no-modern` option is currently ignored. Modern indexes (specs, latest_specs, and prerelease_specs) are always generated.\n",
      @ui.error
  end

end
