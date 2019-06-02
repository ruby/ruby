require_relative 'helper'

class Reline::WithinPipeTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @reader, @writer = IO.pipe((RELINE_TEST_ENCODING rescue Encoding.default_external))
    Reline.input = @reader
    @output = Reline.output = File.open(IO::NULL, 'w')
    @config = Reline.class_variable_get(:@@config)
    @line_editor = Reline.class_variable_get(:@@line_editor)
  end

  def teardown
    Reline.input = STDIN
    Reline.output = STDOUT
    @reader.close
    @writer.close
    @output.close
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
end
