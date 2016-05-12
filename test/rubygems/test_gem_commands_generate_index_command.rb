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

end if ''.respond_to? :to_xs

