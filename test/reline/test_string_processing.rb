require_relative 'helper'

class Reline::LineEditor::StringProcessingTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @prompt = '> '
    @config = Reline::Config.new
    Reline::HISTORY.instance_variable_set(:@config, @config)
    @encoding = (RELINE_TEST_ENCODING rescue Encoding.default_external)
    @line_editor = Reline::LineEditor.new(@config)
    @line_editor.reset(@prompt, @encoding)
  end

  def test_calculate_width
    width = @line_editor.send(:calculate_width, 'Ruby string')
    assert_equal('Ruby string'.size, width)
  end

  def test_calculate_width_with_escape_sequence
    width = @line_editor.send(:calculate_width, "\1\e[31m\2RubyColor\1\e[34m\2 default string \1\e[m\2>", true)
    assert_equal('RubyColor default string >'.size, width)
  end
end
