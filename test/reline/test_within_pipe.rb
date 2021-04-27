require_relative 'helper'

class Reline::WithinPipeTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @input_reader, @writer = IO.pipe((RELINE_TEST_ENCODING rescue Encoding.default_external))
    Reline.input = @input_reader
    @reader, @output_writer = IO.pipe((RELINE_TEST_ENCODING rescue Encoding.default_external))
    @output = Reline.output = @output_writer
    @config = Reline.send(:core).config
    @config.keyseq_timeout *= 600 if defined?(RubyVM::JIT) && RubyVM::JIT.enabled? # for --jit-wait CI
    @line_editor = Reline.send(:core).line_editor
  end

  def teardown
    Reline.input = STDIN
    Reline.output = STDOUT
    Reline.point = 0
    Reline.delete_text
    @input_reader.close
    @writer.close
    @reader.close
    @output_writer.close
    @config.reset
  end

  def test_simple_input
    @writer.write("abc\n")
    assert_equal 'abc', Reline.readmultiline(&proc{ true })
  end

  def test_unknown_macro
    @config.add_default_key_binding('abc'.bytes, :unknown_macro)
    @writer.write("abcd\n")
    assert_equal 'd', Reline.readmultiline(&proc{ true })
  end

  def test_macro_commands_for_moving
    @config.add_default_key_binding("\C-x\C-a".bytes, :beginning_of_line)
    @config.add_default_key_binding("\C-x\C-e".bytes, :end_of_line)
    @config.add_default_key_binding("\C-x\C-f".bytes, :forward_char)
    @config.add_default_key_binding("\C-x\C-b".bytes, :backward_char)
    @config.add_default_key_binding("\C-x\M-f".bytes, :forward_word)
    @config.add_default_key_binding("\C-x\M-b".bytes, :backward_word)
    @writer.write(" def\C-x\C-aabc\C-x\C-e ghi\C-x\C-a\C-x\C-f\C-x\C-f_\C-x\C-b\C-x\C-b_\C-x\C-f\C-x\C-f\C-x\C-f\C-x\M-f_\C-x\M-b\n")
    assert_equal 'a_b_c def_ ghi', Reline.readmultiline(&proc{ true })
  end

  def test_macro_commands_for_editing
    @config.add_default_key_binding("\C-x\C-d".bytes, :delete_char)
    @config.add_default_key_binding("\C-x\C-h".bytes, :backward_delete_char)
    @config.add_default_key_binding("\C-x\C-v".bytes, :quoted_insert)
    #@config.add_default_key_binding("\C-xa".bytes, :self_insert)
    @config.add_default_key_binding("\C-x\C-t".bytes, :transpose_chars)
    @config.add_default_key_binding("\C-x\M-t".bytes, :transpose_words)
    @config.add_default_key_binding("\C-x\M-u".bytes, :upcase_word)
    @config.add_default_key_binding("\C-x\M-l".bytes, :downcase_word)
    @config.add_default_key_binding("\C-x\M-c".bytes, :capitalize_word)
    @writer.write("abcde\C-b\C-b\C-b\C-x\C-d\C-x\C-h\C-x\C-v\C-a\C-f\C-f EF\C-x\C-t gh\C-x\M-t\C-b\C-b\C-b\C-b\C-b\C-b\C-b\C-b\C-x\M-u\C-x\M-l\C-x\M-c\n")
    assert_equal "a\C-aDE gh Fe", Reline.readmultiline(&proc{ true })
  end

  def test_delete_text_in_multiline
    @writer.write("abc\ndef\nxyz\n")
    result = Reline.readmultiline(&proc{ |str|
      if str.include?('xyz')
        Reline.delete_text
        true
      else
        false
      end
    })
    assert_equal "abc\ndef", result
  end
end
