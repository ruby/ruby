# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/mirror_command'

class TestGemCommandsMirrorCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::MirrorCommand.new
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Install the rubygems-mirror%i, @ui.error
  end

end
