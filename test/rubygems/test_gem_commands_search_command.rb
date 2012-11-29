require 'rubygems/test_case'
require 'rubygems/commands/search_command'

class TestGemCommandsSearchCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::SearchCommand.new
  end

  def test_execute
    @cmd.handle_options %w[a]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%REMOTE GEMS%, @ui.output

    assert_empty @ui.error
  end

end

