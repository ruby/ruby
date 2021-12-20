require_relative 'helper'
require 'reline'
require 'stringio'

class Reline::Test < Reline::TestCase
  class DummyCallbackObject
    def call; end
  end

  def setup
    Reline.output_modifier_proc = nil
    Reline.completion_proc = nil
    Reline.prompt_proc = nil
    Reline.auto_indent_proc = nil
    Reline.pre_input_hook = nil
    Reline.dig_perfect_match_proc = nil
  end

  def teardown
    Reline.test_reset
  end

  def test_completion_append_character
    completion_append_character = Reline.completion_append_character

    assert_equal(nil, Reline.completion_append_character)

    Reline.completion_append_character = ""
    assert_equal(nil, Reline.completion_append_character)

    Reline.completion_append_character = "a".encode(Encoding::ASCII)
    assert_equal("a", Reline.completion_append_character)
    assert_equal(get_reline_encoding, Reline.completion_append_character.encoding)

    Reline.completion_append_character = "ba".encode(Encoding::ASCII)
    assert_equal("b", Reline.completion_append_character)
    assert_equal(get_reline_encoding, Reline.completion_append_character.encoding)

    Reline.completion_append_character = "cba".encode(Encoding::ASCII)
    assert_equal("c", Reline.completion_append_character)
    assert_equal(get_reline_encoding, Reline.completion_append_character.encoding)

    Reline.completion_append_character = nil
    assert_equal(nil, Reline.completion_append_character)
  ensure
    Reline.completion_append_character = completion_append_character
  end

  def test_basic_word_break_characters
    basic_word_break_characters = Reline.basic_word_break_characters

    assert_equal(" \t\n`><=;|&{(", Reline.basic_word_break_characters)

    Reline.basic_word_break_characters = "[".encode(Encoding::ASCII)
    assert_equal("[", Reline.basic_word_break_characters)
    assert_equal(get_reline_encoding, Reline.basic_word_break_characters.encoding)
  ensure
    Reline.basic_word_break_characters = basic_word_break_characters
  end

  def test_completer_word_break_characters
    completer_word_break_characters = Reline.completer_word_break_characters

    assert_equal(" \t\n`><=;|&{(", Reline.completer_word_break_characters)

    Reline.completer_word_break_characters = "[".encode(Encoding::ASCII)
    assert_equal("[", Reline.completer_word_break_characters)
    assert_equal(get_reline_encoding, Reline.completer_word_break_characters.encoding)

    assert_nothing_raised { Reline.completer_word_break_characters = '' }
  ensure
    Reline.completer_word_break_characters = completer_word_break_characters
  end

  def test_basic_quote_characters
    basic_quote_characters = Reline.basic_quote_characters

    assert_equal('"\'', Reline.basic_quote_characters)

    Reline.basic_quote_characters = "`".encode(Encoding::ASCII)
    assert_equal("`", Reline.basic_quote_characters)
    assert_equal(get_reline_encoding, Reline.basic_quote_characters.encoding)
  ensure
    Reline.basic_quote_characters = basic_quote_characters
  end

  def test_completer_quote_characters
    completer_quote_characters = Reline.completer_quote_characters

    assert_equal('"\'', Reline.completer_quote_characters)

    Reline.completer_quote_characters = "`".encode(Encoding::ASCII)
    assert_equal("`", Reline.completer_quote_characters)
    assert_equal(get_reline_encoding, Reline.completer_quote_characters.encoding)

    assert_nothing_raised { Reline.completer_quote_characters = '' }
  ensure
    Reline.completer_quote_characters = completer_quote_characters
  end

  def test_filename_quote_characters
    filename_quote_characters = Reline.filename_quote_characters

    assert_equal('', Reline.filename_quote_characters)

    Reline.filename_quote_characters = "\'".encode(Encoding::ASCII)
    assert_equal("\'", Reline.filename_quote_characters)
    assert_equal(get_reline_encoding, Reline.filename_quote_characters.encoding)
  ensure
    Reline.filename_quote_characters = filename_quote_characters
  end

  def test_special_prefixes
    special_prefixes = Reline.special_prefixes

    assert_equal('', Reline.special_prefixes)

    Reline.special_prefixes = "\'".encode(Encoding::ASCII)
    assert_equal("\'", Reline.special_prefixes)
    assert_equal(get_reline_encoding, Reline.special_prefixes.encoding)
  ensure
    Reline.special_prefixes = special_prefixes
  end

  def test_completion_case_fold
    completion_case_fold = Reline.completion_case_fold

    assert_equal(nil, Reline.completion_case_fold)

    Reline.completion_case_fold = true
    assert_equal(true, Reline.completion_case_fold)

    Reline.completion_case_fold = "hoge".encode(Encoding::ASCII)
    assert_equal("hoge", Reline.completion_case_fold)
  ensure
    Reline.completion_case_fold = completion_case_fold
  end

  def test_completion_proc
    skip unless Reline.completion_proc == nil
    # Another test can set Reline.completion_proc

    # assert_equal(nil, Reline.completion_proc)

    dummy_proc = proc {}
    Reline.completion_proc = dummy_proc
    assert_equal(dummy_proc, Reline.completion_proc)

    l = lambda {}
    Reline.completion_proc = l
    assert_equal(l, Reline.completion_proc)

    assert_raise(ArgumentError) { Reline.completion_proc = 42 }
    assert_raise(ArgumentError) { Reline.completion_proc = "hoge" }

    dummy = DummyCallbackObject.new
    Reline.completion_proc = dummy
    assert_equal(dummy, Reline.completion_proc)
  end

  def test_output_modifier_proc
    assert_equal(nil, Reline.output_modifier_proc)

    dummy_proc = proc {}
    Reline.output_modifier_proc = dummy_proc
    assert_equal(dummy_proc, Reline.output_modifier_proc)

    l = lambda {}
    Reline.output_modifier_proc = l
    assert_equal(l, Reline.output_modifier_proc)

    assert_raise(ArgumentError) { Reline.output_modifier_proc = 42 }
    assert_raise(ArgumentError) { Reline.output_modifier_proc = "hoge" }

    dummy = DummyCallbackObject.new
    Reline.output_modifier_proc = dummy
    assert_equal(dummy, Reline.output_modifier_proc)
  end

  def test_prompt_proc
    assert_equal(nil, Reline.prompt_proc)

    dummy_proc = proc {}
    Reline.prompt_proc = dummy_proc
    assert_equal(dummy_proc, Reline.prompt_proc)

    l = lambda {}
    Reline.prompt_proc = l
    assert_equal(l, Reline.prompt_proc)

    assert_raise(ArgumentError) { Reline.prompt_proc = 42 }
    assert_raise(ArgumentError) { Reline.prompt_proc = "hoge" }

    dummy = DummyCallbackObject.new
    Reline.prompt_proc = dummy
    assert_equal(dummy, Reline.prompt_proc)
  end

  def test_auto_indent_proc
    assert_equal(nil, Reline.auto_indent_proc)

    dummy_proc = proc {}
    Reline.auto_indent_proc = dummy_proc
    assert_equal(dummy_proc, Reline.auto_indent_proc)

    l = lambda {}
    Reline.auto_indent_proc = l
    assert_equal(l, Reline.auto_indent_proc)

    assert_raise(ArgumentError) { Reline.auto_indent_proc = 42 }
    assert_raise(ArgumentError) { Reline.auto_indent_proc = "hoge" }

    dummy = DummyCallbackObject.new
    Reline.auto_indent_proc = dummy
    assert_equal(dummy, Reline.auto_indent_proc)
  end

  def test_pre_input_hook
    assert_equal(nil, Reline.pre_input_hook)

    dummy_proc = proc {}
    Reline.pre_input_hook = dummy_proc
    assert_equal(dummy_proc, Reline.pre_input_hook)

    l = lambda {}
    Reline.pre_input_hook = l
    assert_equal(l, Reline.pre_input_hook)
  end

  def test_dig_perfect_match_proc
    assert_equal(nil, Reline.dig_perfect_match_proc)

    dummy_proc = proc {}
    Reline.dig_perfect_match_proc = dummy_proc
    assert_equal(dummy_proc, Reline.dig_perfect_match_proc)

    l = lambda {}
    Reline.dig_perfect_match_proc = l
    assert_equal(l, Reline.dig_perfect_match_proc)

    assert_raise(ArgumentError) { Reline.dig_perfect_match_proc = 42 }
    assert_raise(ArgumentError) { Reline.dig_perfect_match_proc = "hoge" }

    dummy = DummyCallbackObject.new
    Reline.dig_perfect_match_proc = dummy
    assert_equal(dummy, Reline.dig_perfect_match_proc)
  end

  def test_insert_text
    assert_equal('', Reline.line_buffer)
    assert_equal(0, Reline.point)
    Reline.insert_text('abc')
    assert_equal('abc', Reline.line_buffer)
    assert_equal(3, Reline.point)
  end

  def test_delete_text
    assert_equal('', Reline.line_buffer)
    assert_equal(0, Reline.point)
    Reline.insert_text('abc')
    assert_equal('abc', Reline.line_buffer)
    assert_equal(3, Reline.point)
    Reline.delete_text()
    assert_equal('', Reline.line_buffer)
    assert_equal(0, Reline.point)
    Reline.insert_text('abc')
    Reline.delete_text(1)
    assert_equal('a', Reline.line_buffer)
    assert_equal(1, Reline.point)
    Reline.insert_text('defghi')
    Reline.delete_text(2, 2)
    assert_equal('adghi', Reline.line_buffer)
    assert_equal(5, Reline.point)
  end

  def test_set_input_and_output
    assert_raise(TypeError) do
      Reline.input = "This is not a file."
    end
    assert_raise(TypeError) do
      Reline.output = "This is not a file."
    end

    input, to_write = IO.pipe
    to_read, output = IO.pipe
    unless Reline.__send__(:input=, input)
      omit "Setting to input is not effective on #{Reline::IOGate}"
    end
    Reline.output = output

    to_write.write "a\n"
    result = Reline.readline
    to_write.close
    read_text = to_read.read_nonblock(100)
    assert_equal('a', result)
    refute(read_text.empty?)
  ensure
    input&.close
    output&.close
    to_read&.close
  end

  def test_vi_editing_mode
    Reline.vi_editing_mode
    assert_equal(Reline::KeyActor::ViInsert, Reline.send(:core).config.editing_mode.class)
  end

  def test_emacs_editing_mode
    Reline.emacs_editing_mode
    assert_equal(Reline::KeyActor::Emacs, Reline.send(:core).config.editing_mode.class)
  end

  def test_add_dialog_proc
    dummy_proc = proc {}
    Reline.add_dialog_proc(:test_proc, dummy_proc)
    d = Reline.dialog_proc(:test_proc)
    assert_equal(dummy_proc, d.dialog_proc)

    dummy_proc_2 = proc {}
    Reline.add_dialog_proc(:test_proc, dummy_proc_2)
    d = Reline.dialog_proc(:test_proc)
    assert_equal(dummy_proc_2, d.dialog_proc)

    l = lambda {}
    Reline.add_dialog_proc(:test_lambda, l)
    d = Reline.dialog_proc(:test_lambda)
    assert_equal(l, d.dialog_proc)

    assert_equal(nil, Reline.dialog_proc(:test_nothing))

    assert_raise(ArgumentError) { Reline.add_dialog_proc(:error, 42) }
    assert_raise(ArgumentError) { Reline.add_dialog_proc(:error, 'hoge') }
    assert_raise(ArgumentError) { Reline.add_dialog_proc('error', proc {} ) }

    dummy = DummyCallbackObject.new
    Reline.add_dialog_proc(:dummy, dummy)
    d = Reline.dialog_proc(:dummy)
    assert_equal(dummy, d.dialog_proc)
  end

  def test_add_dialog_proc_with_context
    dummy_proc = proc {}
    array = Array.new
    Reline.add_dialog_proc(:test_proc, dummy_proc, array)
    d = Reline.dialog_proc(:test_proc)
    assert_equal(dummy_proc, d.dialog_proc)
    assert_equal(array, d.context)

    Reline.add_dialog_proc(:test_proc, dummy_proc, nil)
    d = Reline.dialog_proc(:test_proc)
    assert_equal(dummy_proc, d.dialog_proc)
    assert_equal(nil, d.context)
  end

  def test_readmultiline
    # readmultiline is module function
    assert_include(Reline.methods, :readmultiline)
    assert_include(Reline.private_instance_methods, :readmultiline)
  end

  def test_readline
    # readline is module function
    assert_include(Reline.methods, :readline)
    assert_include(Reline.private_instance_methods, :readline)
  end

  def test_inner_readline
    # TODO in Reline::Core
  end

  def test_read_io
    # TODO in Reline::Core
  end

  def test_read_escaped_key
    # TODO in Reline::Core
  end

  def test_may_req_ambiguous_char_width
    # TODO in Reline::Core
  end

  def get_reline_encoding
    if encoding = Reline::IOGate.encoding
      encoding
    elsif RUBY_PLATFORM =~ /mswin|mingw/
      Encoding::UTF_8
    else
      Encoding::default_external
    end
  end
end
