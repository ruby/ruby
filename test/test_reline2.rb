require_relative 'helper'
require "reline2"

class Reline2::Test < Reline::TestCase
  def test_completion_append_character
    assert_equal(Reline2.completion_append_character, nil)

    Reline2.completion_append_character = ""
    assert_equal(Reline2.completion_append_character, nil)

    Reline2.completion_append_character = "a"
    assert_equal(Reline2.completion_append_character, "a")
    assert_equal(Reline2.completion_append_character.encoding, Encoding::default_external)

    Reline2.completion_append_character = "ba"
    assert_equal(Reline2.completion_append_character, "b")
    assert_equal(Reline2.completion_append_character.encoding, Encoding::default_external)

    Reline2.completion_append_character = "cba"
    assert_equal(Reline2.completion_append_character, "c")
    assert_equal(Reline2.completion_append_character.encoding, Encoding::default_external)

    Reline2.completion_append_character = nil
    assert_equal(Reline2.completion_append_character, nil)
  end

  def test_basic_word_break_characters
    assert_equal(Reline2.basic_word_break_characters, " \t\n`><=;|&{(")

    Reline2.basic_word_break_characters = "ああ"
    assert_equal(Reline2.basic_word_break_characters, "ああ")
    assert_equal(Reline2.basic_word_break_characters.encoding, Encoding::default_external)
  end

  def test_completer_word_break_characters
    assert_equal(Reline2.completer_word_break_characters, " \t\n`><=;|&{(")

    Reline2.completer_word_break_characters = "ああ"
    assert_equal(Reline2.completer_word_break_characters, "ああ")
    assert_equal(Reline2.completer_word_break_characters.encoding, Encoding::default_external)
  end

  def test_basic_quote_characters
    assert_equal(Reline2.basic_quote_characters, '"\'')

    Reline2.basic_quote_characters = "“"
    assert_equal(Reline2.basic_quote_characters, "“")
    assert_equal(Reline2.basic_quote_characters.encoding, Encoding::default_external)
  end

  def test_completer_quote_characters
    assert_equal(Reline2.completer_quote_characters, '"\'')

    Reline2.completer_quote_characters = "“"
    assert_equal(Reline2.completer_quote_characters, "“")
    assert_equal(Reline2.completer_quote_characters.encoding, Encoding::default_external)
  end

  def test_filename_quote_characters
    assert_equal(Reline2.filename_quote_characters, '')

    Reline2.filename_quote_characters = "\'"
    assert_equal(Reline2.filename_quote_characters, "\'")
    assert_equal(Reline2.filename_quote_characters.encoding, Encoding::default_external)
  end

  def test_special_prefixes
    assert_equal(Reline2.special_prefixes, '')

    Reline2.special_prefixes = "\'"
    assert_equal(Reline2.special_prefixes, "\'")
    assert_equal(Reline2.special_prefixes.encoding, Encoding::default_external)
  end

  def test_completion_case_fold
    assert_equal(Reline2.completion_case_fold, nil)

    Reline2.completion_case_fold = true
    assert_equal(Reline2.completion_case_fold, true)

    Reline2.completion_case_fold = "hoge"
    assert_equal(Reline2.completion_case_fold, "hoge")
  end

  def test_completion_proc
    assert_equal(Reline2.completion_proc, nil)

    p = proc {}
    Reline2.completion_proc = p
    assert_equal(Reline2.completion_proc, p)

    l = lambda {}
    Reline2.completion_proc = l
    assert_equal(Reline2.completion_proc, l)

    assert_raise(ArgumentError) { Reline2.completion_proc = 42 }
    assert_raise(ArgumentError) { Reline2.completion_proc = "hoge" }
  end

  def test_output_modifier_proc
    assert_equal(Reline2.output_modifier_proc, nil)

    p = proc {}
    Reline2.output_modifier_proc = p
    assert_equal(Reline2.output_modifier_proc, p)

    l = lambda {}
    Reline2.output_modifier_proc = l
    assert_equal(Reline2.output_modifier_proc, l)

    assert_raise(ArgumentError) { Reline2.output_modifier_proc = 42 }
    assert_raise(ArgumentError) { Reline2.output_modifier_proc = "hoge" }
  end

  def test_prompt_proc
    assert_equal(Reline2.prompt_proc, nil)

    p = proc {}
    Reline2.prompt_proc = p
    assert_equal(Reline2.prompt_proc, p)

    l = lambda {}
    Reline2.prompt_proc = l
    assert_equal(Reline2.prompt_proc, l)

    assert_raise(ArgumentError) { Reline2.prompt_proc = 42 }
    assert_raise(ArgumentError) { Reline2.prompt_proc = "hoge" }
  end

  def test_auto_indent_proc
    assert_equal(Reline2.auto_indent_proc, nil)

    p = proc {}
    Reline2.auto_indent_proc = p
    assert_equal(Reline2.auto_indent_proc, p)

    l = lambda {}
    Reline2.auto_indent_proc = l
    assert_equal(Reline2.auto_indent_proc, l)

    assert_raise(ArgumentError) { Reline2.auto_indent_proc = 42 }
    assert_raise(ArgumentError) { Reline2.auto_indent_proc = "hoge" }
  end

  def test_pre_input_hook
    assert_equal(Reline2.pre_input_hook, nil)

    p = proc {}
    Reline2.pre_input_hook = p
    assert_equal(Reline2.pre_input_hook, p)

    l = lambda {}
    Reline2.pre_input_hook = l
    assert_equal(Reline2.pre_input_hook, l)

    assert_raise(ArgumentError) { Reline2.pre_input_hook = 42 }
    assert_raise(ArgumentError) { Reline2.pre_input_hook = "hoge" }
  end

  def test_dig_perfect_match_proc
    assert_equal(Reline2.dig_perfect_match_proc, nil)

    p = proc {}
    Reline2.dig_perfect_match_proc = p
    assert_equal(Reline2.dig_perfect_match_proc, p)

    l = lambda {}
    Reline2.dig_perfect_match_proc = l
    assert_equal(Reline2.dig_perfect_match_proc, l)

    assert_raise(ArgumentError) { Reline2.dig_perfect_match_proc = 42 }
    assert_raise(ArgumentError) { Reline2.dig_perfect_match_proc = "hoge" }
  end
end
