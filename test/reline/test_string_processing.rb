require_relative 'helper'

class Reline::LineEditor::StringProcessingTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @prompt = '> '
    @config = Reline::Config.new
    Reline::HISTORY.instance_variable_set(:@config, @config)
    @line_editor = Reline::LineEditor.new(@config)
    @line_editor.reset(@prompt)
  end

  def teardown
    Reline.test_reset
  end

  def test_calculate_width
    width = @line_editor.send(:calculate_width, 'Ruby string')
    assert_equal('Ruby string'.size, width)
  end

  def test_calculate_width_with_escape_sequence
    width = @line_editor.send(:calculate_width, "\1\e[31m\2RubyColor\1\e[34m\2 default string \1\e[m\2>", true)
    assert_equal('RubyColor default string >'.size, width)
  end

  def test_completion_proc_with_preposing_and_postposing
    buf = ['def hoge', '  puts :aaa', 'end']

    @line_editor.instance_variable_set(:@is_multiline, true)
    @line_editor.instance_variable_set(:@buffer_of_lines, buf)
    @line_editor.instance_variable_set(:@byte_pointer, 6)
    @line_editor.instance_variable_set(:@line_index, 1)
    completion_proc_called = false
    @line_editor.instance_variable_set(:@completion_proc, proc { |target, pre, post|
      assert_equal('puts', target)
      assert_equal("def hoge\n  ", pre)
      assert_equal(" :aaa\nend", post)
      completion_proc_called = true
    })

    assert_equal(["def hoge\n  ", 'puts', " :aaa\nend", nil], @line_editor.retrieve_completion_block)
    @line_editor.__send__(:call_completion_proc, "def hoge\n  ", 'puts', " :aaa\nend", nil)
    assert(completion_proc_called)
  end
end
