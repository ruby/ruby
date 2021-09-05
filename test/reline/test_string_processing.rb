require_relative 'helper'

class Reline::LineEditor::StringProcessingTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @prompt = '> '
    @config = Reline::Config.new
    Reline::HISTORY.instance_variable_set(:@config, @config)
    @encoding = (RELINE_TEST_ENCODING rescue Encoding.default_external)
    @line_editor = Reline::LineEditor.new(@config, @encoding)
    @line_editor.reset(@prompt, encoding: @encoding)
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
    @line_editor.instance_variable_set(:@line, buf[1])
    @line_editor.instance_variable_set(:@byte_pointer, 3)
    @line_editor.instance_variable_set(:@cursor, 3)
    @line_editor.instance_variable_set(:@cursor_max, 11)
    @line_editor.instance_variable_set(:@line_index, 1)
    @line_editor.instance_variable_set(:@completion_proc, proc { |target|
      assert_equal('p', target)
    })
    @line_editor.__send__(:call_completion_proc)

    @line_editor.instance_variable_set(:@is_multiline, true)
    @line_editor.instance_variable_set(:@buffer_of_lines, buf)
    @line_editor.instance_variable_set(:@line, buf[1])
    @line_editor.instance_variable_set(:@byte_pointer, 6)
    @line_editor.instance_variable_set(:@cursor, 6)
    @line_editor.instance_variable_set(:@cursor_max, 11)
    @line_editor.instance_variable_set(:@line_index, 1)
    @line_editor.instance_variable_set(:@completion_proc, proc { |target, pre, post|
      assert_equal('puts', target)
      assert_equal("def hoge\n  ", pre)
      assert_equal(" :aaa\nend", post)
    })
    @line_editor.__send__(:call_completion_proc)

    @line_editor.instance_variable_set(:@line, buf[0])
    @line_editor.instance_variable_set(:@byte_pointer, 6)
    @line_editor.instance_variable_set(:@cursor, 6)
    @line_editor.instance_variable_set(:@cursor_max, 8)
    @line_editor.instance_variable_set(:@line_index, 0)
    @line_editor.instance_variable_set(:@completion_proc, proc { |target, pre, post|
      assert_equal('ho', target)
      assert_equal('def ', pre)
      assert_equal("ge\n  puts :aaa\nend", post)
    })
    @line_editor.__send__(:call_completion_proc)

    @line_editor.instance_variable_set(:@line, buf[2])
    @line_editor.instance_variable_set(:@byte_pointer, 1)
    @line_editor.instance_variable_set(:@cursor, 1)
    @line_editor.instance_variable_set(:@cursor_max, 3)
    @line_editor.instance_variable_set(:@line_index, 2)
    @line_editor.instance_variable_set(:@completion_proc, proc { |target, pre, post|
      assert_equal('e', target)
      assert_equal("def hoge\n  puts :aaa\n", pre)
      assert_equal('nd', post)
    })
    @line_editor.__send__(:call_completion_proc)
  end
end
