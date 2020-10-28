require_relative 'helper'
require "reline"

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

    p = proc {}
    Reline.completion_proc = p
    assert_equal(p, Reline.completion_proc)

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

    p = proc {}
    Reline.output_modifier_proc = p
    assert_equal(p, Reline.output_modifier_proc)

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

    p = proc {}
    Reline.prompt_proc = p
    assert_equal(p, Reline.prompt_proc)

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

    p = proc {}
    Reline.auto_indent_proc = p
    assert_equal(p, Reline.auto_indent_proc)

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

    p = proc {}
    Reline.pre_input_hook = p
    assert_equal(p, Reline.pre_input_hook)

    l = lambda {}
    Reline.pre_input_hook = l
    assert_equal(l, Reline.pre_input_hook)
  end

  def test_dig_perfect_match_proc
    assert_equal(nil, Reline.dig_perfect_match_proc)

    p = proc {}
    Reline.dig_perfect_match_proc = p
    assert_equal(p, Reline.dig_perfect_match_proc)

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
    # TODO
  end

  def test_line_buffer
    # TODO
  end

  def test_point
    # TODO
  end

  def test_input=
    # TODO
    assert_raise(TypeError) do
      Reline.input = "This is not a file."
    end
  end

  def test_output=
    # TODO
    assert_raise(TypeError) do
      Reline.output = "This is not a file."
    end
  end

  def test_vi_editing_mode
    Reline.vi_editing_mode
    assert_equal(Reline::KeyActor::ViInsert, Reline.send(:core).config.editing_mode.class)
  end

  def test_emacs_editing_mode
    Reline.emacs_editing_mode
    assert_equal(Reline::KeyActor::Emacs, Reline.send(:core).config.editing_mode.class)
  end

  def test_editing_mode
    # TODO
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
    RUBY_PLATFORM =~ /mswin|mingw/ ? Encoding::UTF_8 : Encoding::default_external
  end
end
