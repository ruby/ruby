# coding: UTF-8
# frozen_string_literal: false

require 'rdoc/test_case'

class TestRDocRubyLex < RDoc::TestCase

  def setup
    @TK = RDoc::RubyToken
  end

  def test_class_tokenize
    tokens = RDoc::RubyLex.tokenize "def x() end", nil

    expected = [
      @TK::TkDEF       .new( 0, 1,  0, "def"),
      @TK::TkSPACE     .new( 3, 1,  3, " "),
      @TK::TkIDENTIFIER.new( 4, 1,  4, "x"),
      @TK::TkLPAREN    .new( 5, 1,  5, "("),
      @TK::TkRPAREN    .new( 6, 1,  6, ")"),
      @TK::TkSPACE     .new( 7, 1,  7, " "),
      @TK::TkEND       .new( 8, 1,  8, "end"),
      @TK::TkNL        .new(11, 1, 11, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize___END__
    tokens = RDoc::RubyLex.tokenize '__END__', nil

    expected = [
      @TK::TkEND_OF_SCRIPT.new(0, 1, 0, '__END__'),
      @TK::TkNL           .new(7, 1, 7, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_character_literal
    tokens = RDoc::RubyLex.tokenize "?\\", nil

    expected = [
      @TK::TkCHAR.new( 0, 1,  0, "?\\"),
      @TK::TkNL  .new( 2, 1,  2, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_def_heredoc
    tokens = RDoc::RubyLex.tokenize <<-'RUBY', nil
def x
  <<E
Line 1
Line 2
E
end
    RUBY

    expected = [
      @TK::TkDEF       .new( 0, 1,  0, 'def'),
      @TK::TkSPACE     .new( 3, 1,  3, ' '),
      @TK::TkIDENTIFIER.new( 4, 1,  4, 'x'),
      @TK::TkNL        .new( 5, 1,  5, "\n"),
      @TK::TkSPACE     .new( 6, 2,  0, '  '),
      @TK::TkHEREDOC   .new( 8, 2,  2,
                            %Q{<<E\nLine 1\nLine 2\nE}),
      @TK::TkNL        .new(27, 5, 28, "\n"),
      @TK::TkEND       .new(28, 6,  0, 'end'),
      @TK::TkNL        .new(31, 6, 28, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_hash_symbol
    tokens = RDoc::RubyLex.tokenize '{ class:"foo" }', nil

    expected = [
      @TK::TkLBRACE    .new( 0, 1,  0, '{'),
      @TK::TkSPACE     .new( 1, 1,  1, ' '),
      @TK::TkIDENTIFIER.new( 2, 1,  2, 'class'),
      @TK::TkSYMBEG    .new( 7, 1,  7, ':'),
      @TK::TkSTRING    .new( 8, 1,  8, '"foo"'),
      @TK::TkSPACE     .new(13, 1, 13, ' '),
      @TK::TkRBRACE    .new(14, 1, 14, '}'),
      @TK::TkNL        .new(15, 1, 15, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_heredoc_CR_NL
    tokens = RDoc::RubyLex.tokenize <<-RUBY, nil
string = <<-STRING\r
Line 1\r
Line 2\r
  STRING\r
    RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'string'),
      @TK::TkSPACE     .new( 6, 1,  6, ' '),
      @TK::TkASSIGN    .new( 7, 1,  7, '='),
      @TK::TkSPACE     .new( 8, 1,  8, ' '),
      @TK::TkHEREDOC   .new( 9, 1,  9,
                            %Q{<<-STRING\nLine 1\nLine 2\n  STRING}),
      @TK::TkSPACE     .new(44, 4, 45, "\r"),
      @TK::TkNL        .new(45, 4, 46, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_heredoc_call
    tokens = RDoc::RubyLex.tokenize <<-'RUBY', nil
string = <<-STRING.chomp
Line 1
Line 2
  STRING
    RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'string'),
      @TK::TkSPACE     .new( 6, 1,  6, ' '),
      @TK::TkASSIGN    .new( 7, 1,  7, '='),
      @TK::TkSPACE     .new( 8, 1,  8, ' '),
      @TK::TkSTRING    .new( 9, 1,  9, %Q{"Line 1\nLine 2\n"}),
      @TK::TkDOT       .new(41, 4, 42, '.'),
      @TK::TkIDENTIFIER.new(42, 4, 43, 'chomp'),
      @TK::TkNL        .new(47, 4, 48, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_heredoc_indent
    tokens = RDoc::RubyLex.tokenize <<-'RUBY', nil
string = <<-STRING
Line 1
Line 2
  STRING
    RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'string'),
      @TK::TkSPACE     .new( 6, 1,  6, ' '),
      @TK::TkASSIGN    .new( 7, 1,  7, '='),
      @TK::TkSPACE     .new( 8, 1,  8, ' '),
      @TK::TkHEREDOC   .new( 9, 1,  9,
                            %Q{<<-STRING\nLine 1\nLine 2\n  STRING}),
      @TK::TkNL        .new(41, 4, 42, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_heredoc_missing_end
    e = assert_raises RDoc::RubyLex::Error do
      RDoc::RubyLex.tokenize <<-'RUBY', nil
>> string1 = <<-TXT
>" That's swell
>" TXT
      RUBY
    end

    assert_equal 'Missing terminating TXT for string', e.message
  end

  def test_class_tokenize_heredoc_percent_N
    tokens = RDoc::RubyLex.tokenize <<-'RUBY', nil
a b <<-U
%N
U
    RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'a'),
      @TK::TkSPACE     .new( 1, 1,  1, ' '),
      @TK::TkIDENTIFIER.new( 2, 1,  2, 'b'),
      @TK::TkSPACE     .new( 3, 1,  3, ' '),
      @TK::TkHEREDOC   .new( 4, 1,  4, %Q{<<-U\n%N\nU}),
      @TK::TkNL        .new(13, 3, 14, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_identifier_high_unicode
    tokens = RDoc::RubyLex.tokenize '𝖒', nil

    expected = @TK::TkIDENTIFIER.new(0, 1, 0, '𝖒')

    assert_equal expected, tokens.first
  end

  def test_class_tokenize_percent_1
    tokens = RDoc::RubyLex.tokenize 'v%10==10', nil

    expected = [
      @TK::TkIDENTIFIER.new(0, 1, 0, 'v'),
      @TK::TkMOD.new(       1, 1, 1, '%'),
      @TK::TkINTEGER.new(   2, 1, 2, '10'),
      @TK::TkEQ.new(        4, 1, 4, '=='),
      @TK::TkINTEGER.new(   6, 1, 6, '10'),
      @TK::TkNL.new(        8, 1, 8, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_r
    tokens = RDoc::RubyLex.tokenize '%r[hi]', nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, '%r[hi]'),
      @TK::TkNL    .new( 6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_w
    tokens = RDoc::RubyLex.tokenize '%w[hi]', nil

    expected = [
      @TK::TkDSTRING.new( 0, 1,  0, '%w[hi]'),
      @TK::TkNL     .new( 6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_w_quote
    tokens = RDoc::RubyLex.tokenize '%w"hi"', nil

    expected = [
      @TK::TkDSTRING.new( 0, 1,  0, '%w"hi"'),
      @TK::TkNL     .new( 6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_regexp
    tokens = RDoc::RubyLex.tokenize "/hay/", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/hay/"),
      @TK::TkNL    .new( 5, 1,  5, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_regexp_options
    tokens = RDoc::RubyLex.tokenize "/hAY/i", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/hAY/i"),
      @TK::TkNL    .new( 6, 1,  6, "\n"),
    ]

    assert_equal expected, tokens

    tokens = RDoc::RubyLex.tokenize "/hAY/ix", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/hAY/ix"),
      @TK::TkNL    .new( 7, 1,  7, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_regexp_backref
    tokens = RDoc::RubyLex.tokenize "/[csh](..) [csh]\\1 in/", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/[csh](..) [csh]\\1 in/"),
      @TK::TkNL    .new(22, 1, 22, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_regexp_escape
    tokens = RDoc::RubyLex.tokenize "/\\//", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/\\//"),
      @TK::TkNL    .new( 4, 1,  4, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_string
    tokens = RDoc::RubyLex.tokenize "'hi'", nil

    expected = [
      @TK::TkSTRING.new( 0, 1,  0, "'hi'"),
      @TK::TkNL    .new( 4, 1,  4, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_string_escape
    tokens = RDoc::RubyLex.tokenize '"\\n"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\n\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\r"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\r\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\f"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\f\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\\\"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\\\\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\t"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\t\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\v"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\v\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\a\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\e"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\e\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\b"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\b\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\s"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\s\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\d"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\d\""), tokens.first

  end

  def test_class_tokenize_string_escape_control
    tokens = RDoc::RubyLex.tokenize '"\\C-a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\C-a\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\c\\a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\c\\a\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\C-\\M-a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\C-\\M-a\""), tokens.first
  end

  def test_class_tokenize_string_escape_meta
    tokens = RDoc::RubyLex.tokenize '"\\M-a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\M-a\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\M-\\C-a"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\M-\\C-a\""), tokens.first
  end

  def test_class_tokenize_string_escape_hexadecimal
    tokens = RDoc::RubyLex.tokenize '"\\x0"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\x0\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\x00"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\x00\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\x000"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\x000\""), tokens.first
  end

  def test_class_tokenize_string_escape_octal
    tokens = RDoc::RubyLex.tokenize '"\\0"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\0\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\00"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\00\""), tokens.first

    tokens = RDoc::RubyLex.tokenize '"\\000"', nil
    assert_equal @TK::TkSTRING.new( 0, 1,  0, "\"\\000\""), tokens.first
  end

  def test_class_tokenize_symbol
    tokens = RDoc::RubyLex.tokenize 'scope module: :v1', nil

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'scope'),
      @TK::TkSPACE     .new( 5, 1,  5, ' '),
      @TK::TkIDENTIFIER.new( 6, 1,  6, 'module'),
      @TK::TkCOLON     .new(12, 1, 12, ':'),
      @TK::TkSPACE     .new(13, 1, 13, ' '),
      @TK::TkSYMBEG    .new(14, 1, 14, ':'),
      @TK::TkIDENTIFIER.new(15, 1, 15, 'v1'),
      @TK::TkNL        .new(17, 1, 17, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_unary_minus
    ruby_lex = RDoc::RubyLex.new("-1", nil)
    assert_equal("-1", ruby_lex.token.value)

    ruby_lex = RDoc::RubyLex.new("a[-2]", nil)
    2.times { ruby_lex.token } # skip "a" and "["
    assert_equal("-2", ruby_lex.token.value)

    ruby_lex = RDoc::RubyLex.new("a[0..-12]", nil)
    4.times { ruby_lex.token } # skip "a", "[", "0", and ".."
    assert_equal("-12", ruby_lex.token.value)

    ruby_lex = RDoc::RubyLex.new("0+-0.1", nil)
    2.times { ruby_lex.token } # skip "0" and "+"
    assert_equal("-0.1", ruby_lex.token.value)
  end

end

