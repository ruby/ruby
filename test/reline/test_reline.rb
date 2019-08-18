require_relative 'helper'
require "reline"

class Reline::Test < Reline::TestCase
  def setup
  end

  def teardown
    Reline.test_reset
  end

  def test_completion_append_character
    assert_equal(Reline.completion_append_character, nil)

    Reline.completion_append_character = ""
    assert_equal(Reline.completion_append_character, nil)

    Reline.completion_append_character = "a"
    assert_equal(Reline.completion_append_character, "a")
    assert_equal(Reline.completion_append_character.encoding, Encoding::default_external)

    Reline.completion_append_character = "ba"
    assert_equal(Reline.completion_append_character, "b")
    assert_equal(Reline.completion_append_character.encoding, Encoding::default_external)

    Reline.completion_append_character = "cba"
    assert_equal(Reline.completion_append_character, "c")
    assert_equal(Reline.completion_append_character.encoding, Encoding::default_external)

    Reline.completion_append_character = nil
    assert_equal(Reline.completion_append_character, nil)
  end

  def test_basic_word_break_characters
    assert_equal(Reline.basic_word_break_characters, " \t\n`><=;|&{(")

    Reline.basic_word_break_characters = "["
    assert_equal(Reline.basic_word_break_characters, "[")
    assert_equal(Reline.basic_word_break_characters.encoding, Encoding::default_external)
  end

  def test_completer_word_break_characters
    assert_equal(Reline.completer_word_break_characters, " \t\n`><=;|&{(")

    Reline.completer_word_break_characters = "["
    assert_equal(Reline.completer_word_break_characters, "[")
    assert_equal(Reline.completer_word_break_characters.encoding, Encoding::default_external)
  end

  def test_basic_quote_characters
    assert_equal(Reline.basic_quote_characters, '"\'')

    Reline.basic_quote_characters = "`"
    assert_equal(Reline.basic_quote_characters, "`")
    assert_equal(Reline.basic_quote_characters.encoding, Encoding::default_external)
  end

  def test_completer_quote_characters
    assert_equal(Reline.completer_quote_characters, '"\'')

    Reline.completer_quote_characters = "`"
    assert_equal(Reline.completer_quote_characters, "`")
    assert_equal(Reline.completer_quote_characters.encoding, Encoding::default_external)
  end

  def test_filename_quote_characters
    assert_equal(Reline.filename_quote_characters, '')

    Reline.filename_quote_characters = "\'"
    assert_equal(Reline.filename_quote_characters, "\'")
    assert_equal(Reline.filename_quote_characters.encoding, Encoding::default_external)
  end

  def test_special_prefixes
    assert_equal(Reline.special_prefixes, '')

    Reline.special_prefixes = "\'"
    assert_equal(Reline.special_prefixes, "\'")
    assert_equal(Reline.special_prefixes.encoding, Encoding::default_external)
  end

  def test_completion_case_fold
    assert_equal(Reline.completion_case_fold, nil)

    Reline.completion_case_fold = true
    assert_equal(Reline.completion_case_fold, true)

    Reline.completion_case_fold = "hoge"
    assert_equal(Reline.completion_case_fold, "hoge")
  end

  def test_completion_proc
    assert_equal(Reline.completion_proc, nil)

    p = proc {}
    Reline.completion_proc = p
    assert_equal(Reline.completion_proc, p)

    l = lambda {}
    Reline.completion_proc = l
    assert_equal(Reline.completion_proc, l)

    assert_raise(ArgumentError) { Reline.completion_proc = 42 }
    assert_raise(ArgumentError) { Reline.completion_proc = "hoge" }
  end

  def test_output_modifier_proc
    assert_equal(Reline.output_modifier_proc, nil)

    p = proc {}
    Reline.output_modifier_proc = p
    assert_equal(Reline.output_modifier_proc, p)

    l = lambda {}
    Reline.output_modifier_proc = l
    assert_equal(Reline.output_modifier_proc, l)

    assert_raise(ArgumentError) { Reline.output_modifier_proc = 42 }
    assert_raise(ArgumentError) { Reline.output_modifier_proc = "hoge" }
  end

  def test_prompt_proc
    assert_equal(Reline.prompt_proc, nil)

    p = proc {}
    Reline.prompt_proc = p
    assert_equal(Reline.prompt_proc, p)

    l = lambda {}
    Reline.prompt_proc = l
    assert_equal(Reline.prompt_proc, l)

    assert_raise(ArgumentError) { Reline.prompt_proc = 42 }
    assert_raise(ArgumentError) { Reline.prompt_proc = "hoge" }
  end

  def test_auto_indent_proc
    assert_equal(Reline.auto_indent_proc, nil)

    p = proc {}
    Reline.auto_indent_proc = p
    assert_equal(Reline.auto_indent_proc, p)

    l = lambda {}
    Reline.auto_indent_proc = l
    assert_equal(Reline.auto_indent_proc, l)

    assert_raise(ArgumentError) { Reline.auto_indent_proc = 42 }
    assert_raise(ArgumentError) { Reline.auto_indent_proc = "hoge" }
  end

  def test_pre_input_hook
    assert_equal(Reline.pre_input_hook, nil)

    p = proc {}
    Reline.pre_input_hook = p
    assert_equal(Reline.pre_input_hook, p)

    l = lambda {}
    Reline.pre_input_hook = l
    assert_equal(Reline.pre_input_hook, l)
  end

  def test_dig_perfect_match_proc
    assert_equal(Reline.dig_perfect_match_proc, nil)

    p = proc {}
    Reline.dig_perfect_match_proc = p
    assert_equal(Reline.dig_perfect_match_proc, p)

    l = lambda {}
    Reline.dig_perfect_match_proc = l
    assert_equal(Reline.dig_perfect_match_proc, l)

    assert_raise(ArgumentError) { Reline.dig_perfect_match_proc = 42 }
    assert_raise(ArgumentError) { Reline.dig_perfect_match_proc = "hoge" }
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
    assert_equal(Reline.send(:core).config.editing_mode.class, Reline::KeyActor::ViInsert)
  end

  def test_emacs_editing_mode
    Reline.emacs_editing_mode
    assert_equal(Reline.send(:core).config.editing_mode.class, Reline::KeyActor::Emacs)
  end

  def test_editing_mode
    # TODO
  end

  def test_readmultiline
    # TODO
  end

  def test_readline
    # TODO
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
end
