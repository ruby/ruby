# coding: UTF-8
# frozen_string_literal: false

require 'rdoc/test_case'

class TestRDocRubyLex < RDoc::TestCase

  def setup
    @TK = RDoc::RubyToken
  end

  def test_token_position
    tokens = RDoc::RubyLex.tokenize '[ 1, :a, nil ]', nil

    assert_equal '[', tokens[0].text
    assert_equal 0, tokens[0].seek
    assert_equal 1, tokens[0].line_no
    assert_equal 0, tokens[0].char_no
    assert_equal '1', tokens[2].text
    assert_equal 2, tokens[2].seek
    assert_equal 1, tokens[2].line_no
    assert_equal 2, tokens[2].char_no
    assert_equal ':a', tokens[5].text
    assert_equal 5, tokens[5].seek
    assert_equal 1, tokens[5].line_no
    assert_equal 5, tokens[5].char_no
    assert_equal 'nil', tokens[8].text
    assert_equal 9, tokens[8].seek
    assert_equal 1, tokens[8].line_no
    assert_equal 9, tokens[8].char_no
    assert_equal ']', tokens[10].text
    assert_equal 13, tokens[10].seek
    assert_equal 1, tokens[10].line_no
    assert_equal 13, tokens[10].char_no
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

  def test_class_tokenize___ENCODING__
    tokens = RDoc::RubyLex.tokenize '__ENCODING__', nil

    expected = [
      @TK::Tk__ENCODING__.new( 0, 1,  0, '__ENCODING__'),
      @TK::TkNL          .new(12, 1, 12, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_character_literal
    tokens = RDoc::RubyLex.tokenize "?c", nil

    expected = [
      @TK::TkCHAR.new( 0, 1,  0, "?c"),
      @TK::TkNL  .new( 2, 1,  2, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_character_literal_with_escape
    tokens = RDoc::RubyLex.tokenize "?\\s", nil

    expected = [
      @TK::TkCHAR.new( 0, 1,  0, "?\\s"),
      @TK::TkNL  .new( 3, 1,  3, "\n"),
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

      @TK::TkHEREDOCBEG.new( 8, 2,  2, '<<E'),
      @TK::TkNL        .new(11, 2,  6, "\n"),
      @TK::TkHEREDOC   .new(11, 2,  6, "Line 1\nLine 2\n"),
      @TK::TkHEREDOCEND.new(27, 5, 26, "E\n"),
      @TK::TkEND       .new(28, 6,  0, 'end'),
      @TK::TkNL        .new(31, 6, 28, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_reserved_keyword_with_args
    tokens = RDoc::RubyLex.tokenize <<-'RUBY', nil
yield :foo
super :bar
defined? :baz
    RUBY

    expected = [
      @TK::TkYIELD  .new( 0, 1,  0, "yield"),
      @TK::TkSPACE  .new( 5, 1,  5, " "),
      @TK::TkSYMBOL .new( 6, 1,  6, ":foo"),
      @TK::TkNL     .new(10, 1, 10,  "\n"),
      @TK::TkSUPER  .new(11, 2,  0, "super"),
      @TK::TkSPACE  .new(16, 2,  5, " "),
      @TK::TkSYMBOL .new(17, 2,  6, ":bar"),
      @TK::TkNL     .new(21, 2, 11,  "\n"),
      @TK::TkDEFINED.new(22, 3,  0, "defined?"),
      @TK::TkSPACE  .new(30, 3,  8, " "),
      @TK::TkSYMBOL .new(31, 3,  9, ":baz"),
      @TK::TkNL     .new(35, 3, 22,  "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_hash_symbol
    tokens = RDoc::RubyLex.tokenize '{ class:"foo" }', nil

    expected = [
      @TK::TkLBRACE.new( 0, 1,  0, '{'),
      @TK::TkSPACE .new( 1, 1,  1, ' '),
      @TK::TkSYMBOL.new( 2, 1,  2, 'class:'),
      @TK::TkSTRING.new( 8, 1,  8, '"foo"'),
      @TK::TkSPACE .new(13, 1, 13, ' '),
      @TK::TkRBRACE.new(14, 1, 14, '}'),
      @TK::TkNL    .new(15, 1, 15, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_double_colon_is_not_hash_symbol
    tokens = RDoc::RubyLex.tokenize 'self.class::Row', nil

    expected = [
      @TK::TkSELF      .new( 0, 1,  0, "self"),
      @TK::TkDOT       .new( 4, 1,  4, "."),
      @TK::TkIDENTIFIER.new( 5, 1,  5, "class"),
      @TK::TkCOLON2    .new(10, 1, 10, "::"),
      @TK::TkCONSTANT  .new(12, 1, 12, "Row"),
      @TK::TkNL        .new(15, 1, 15, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_safe_nav_operator
    tokens = RDoc::RubyLex.tokenize 'receiver&.meth', nil

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, "receiver"),
      @TK::TkSAFENAV   .new( 8, 1,  8, "&."),
      @TK::TkIDENTIFIER.new(10, 1, 10, "meth"),
      @TK::TkNL        .new(14, 1, 14, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_hash_rocket
    tokens = RDoc::RubyLex.tokenize '{ :class => "foo" }', nil

    expected = [
      @TK::TkLBRACE    .new( 0, 1,  0, '{'),
      @TK::TkSPACE     .new( 1, 1,  1, ' '),
      @TK::TkSYMBOL    .new( 2, 1,  2, ':class'),
      @TK::TkSPACE     .new( 8, 1,  8, ' '),
      @TK::TkHASHROCKET.new( 9, 1,  9, '=>'),
      @TK::TkSPACE     .new(11, 1, 11, ' '),
      @TK::TkSTRING    .new(12, 1, 12, '"foo"'),
      @TK::TkSPACE     .new(17, 1, 17, ' '),
      @TK::TkRBRACE    .new(18, 1, 18, '}'),
      @TK::TkNL        .new(19, 1, 19, "\n"),
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
      @TK::TkHEREDOCBEG.new( 9, 1,  9, '<<-STRING'),
      @TK::TkSPACE     .new(18, 1, 18, "\r"),
      @TK::TkNL        .new(19, 1, 19, "\n"),
      @TK::TkHEREDOC   .new(19, 1, 19,
                            %Q{Line 1\nLine 2\n}),
      @TK::TkHEREDOCEND.new(45, 4, 36, "  STRING\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_opassign
    tokens = RDoc::RubyLex.tokenize <<'RUBY', nil
a %= b
a /= b
a -= b
a += b
a |= b
a &= b
a >>= b
a <<= b
a *= b
a &&= b
a ||= b
a **= b
RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1, 0, "a"),
      @TK::TkSPACE     .new( 1, 1, 1, " "),
      @TK::TkOPASGN    .new( 2, 1, 2, "%"),
      @TK::TkSPACE     .new( 4, 1, 4, " "),
      @TK::TkIDENTIFIER.new( 5, 1, 5, "b"),
      @TK::TkNL        .new( 6, 1, 6, "\n"),
      @TK::TkIDENTIFIER.new( 7, 2, 0, "a"),
      @TK::TkSPACE     .new( 8, 2, 1, " "),
      @TK::TkOPASGN    .new( 9, 2, 2, "/"),
      @TK::TkSPACE     .new( 11, 2, 4, " "),
      @TK::TkIDENTIFIER.new( 12, 2, 5, "b"),
      @TK::TkNL        .new( 13, 2, 7, "\n"),
      @TK::TkIDENTIFIER.new( 14, 3, 0, "a"),
      @TK::TkSPACE     .new( 15, 3, 1, " "),
      @TK::TkOPASGN    .new( 16, 3, 2, "-"),
      @TK::TkSPACE     .new( 18, 3, 4, " "),
      @TK::TkIDENTIFIER.new( 19, 3, 5, "b"),
      @TK::TkNL        .new( 20, 3, 14, "\n"),
      @TK::TkIDENTIFIER.new( 21, 4, 0, "a"),
      @TK::TkSPACE     .new( 22, 4, 1, " "),
      @TK::TkOPASGN    .new( 23, 4, 2, "+"),
      @TK::TkSPACE     .new( 25, 4, 4, " "),
      @TK::TkIDENTIFIER.new( 26, 4, 5, "b"),
      @TK::TkNL        .new( 27, 4, 21, "\n"),
      @TK::TkIDENTIFIER.new( 28, 5, 0, "a"),
      @TK::TkSPACE     .new( 29, 5, 1, " "),
      @TK::TkOPASGN    .new( 30, 5, 2, "|"),
      @TK::TkSPACE     .new( 32, 5, 4, " "),
      @TK::TkIDENTIFIER.new( 33, 5, 5, "b"),
      @TK::TkNL        .new( 34, 5, 28, "\n"),
      @TK::TkIDENTIFIER.new( 35, 6, 0, "a"),
      @TK::TkSPACE     .new( 36, 6, 1, " "),
      @TK::TkOPASGN    .new( 37, 6, 2, "&"),
      @TK::TkSPACE     .new( 39, 6, 4, " "),
      @TK::TkIDENTIFIER.new( 40, 6, 5, "b"),
      @TK::TkNL        .new( 41, 6, 35, "\n"),
      @TK::TkIDENTIFIER.new( 42, 7, 0, "a"),
      @TK::TkSPACE     .new( 43, 7, 1, " "),
      @TK::TkOPASGN    .new( 44, 7, 2, ">>"),
      @TK::TkSPACE     .new( 47, 7, 5, " "),
      @TK::TkIDENTIFIER.new( 48, 7, 6, "b"),
      @TK::TkNL        .new( 49, 7, 42, "\n"),
      @TK::TkIDENTIFIER.new( 50, 8, 0, "a"),
      @TK::TkSPACE     .new( 51, 8, 1, " "),
      @TK::TkOPASGN    .new( 52, 8, 2, "<<"),
      @TK::TkSPACE     .new( 55, 8, 5, " "),
      @TK::TkIDENTIFIER.new( 56, 8, 6, "b"),
      @TK::TkNL        .new( 57, 8, 50, "\n"),
      @TK::TkIDENTIFIER.new( 58, 9, 0, "a"),
      @TK::TkSPACE     .new( 59, 9, 1, " "),
      @TK::TkOPASGN    .new( 60, 9, 2, "*"),
      @TK::TkSPACE     .new( 62, 9, 4, " "),
      @TK::TkIDENTIFIER.new( 63, 9, 5, "b"),
      @TK::TkNL        .new( 64, 9, 58, "\n"),
      @TK::TkIDENTIFIER.new( 65, 10, 0, "a"),
      @TK::TkSPACE     .new( 66, 10, 1, " "),
      @TK::TkOPASGN    .new( 67, 10, 2, "&&"),
      @TK::TkSPACE     .new( 70, 10, 5, " "),
      @TK::TkIDENTIFIER.new( 71, 10, 6, "b"),
      @TK::TkNL        .new( 72, 10, 65, "\n"),
      @TK::TkIDENTIFIER.new( 73, 11, 0, "a"),
      @TK::TkSPACE     .new( 74, 11, 1, " "),
      @TK::TkOPASGN    .new( 75, 11, 2, "||"),
      @TK::TkSPACE     .new( 78, 11, 5, " "),
      @TK::TkIDENTIFIER.new( 79, 11, 6, "b"),
      @TK::TkNL        .new( 80, 11, 73, "\n"),
      @TK::TkIDENTIFIER.new( 81, 12, 0, "a"),
      @TK::TkSPACE     .new( 82, 12, 1, " "),
      @TK::TkOPASGN    .new( 83, 12, 2, "**"),
      @TK::TkSPACE     .new( 86, 12, 5, " "),
      @TK::TkIDENTIFIER.new( 87, 12, 6, "b"),
      @TK::TkNL        .new( 88, 12, 81, "\n"),
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
      @TK::TkHEREDOCBEG.new( 9, 1,  9, '<<-STRING'),
      @TK::TkDOT       .new(18, 1, 18, '.'),
      @TK::TkIDENTIFIER.new(19, 1, 19, 'chomp'),
      @TK::TkNL        .new(24, 1, 24, "\n"),
      @TK::TkHEREDOC   .new(24, 1, 24, "Line 1\nLine 2\n"),
      @TK::TkHEREDOCEND.new(47, 4, 39, "  STRING\n"),
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


      @TK::TkHEREDOCBEG.new( 9, 1,  9, '<<-STRING'),
      @TK::TkNL        .new(18, 1, 18, "\n"),
      @TK::TkHEREDOC   .new(18, 1, 18, "Line 1\nLine 2\n"),
      @TK::TkHEREDOCEND.new(41, 4, 33, "  STRING\n")
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
      @TK::TkHEREDOCBEG.new( 4, 1,  4, '<<-U'),
      @TK::TkNL        .new( 8, 1,  8, "\n"),
      @TK::TkHEREDOC   .new( 8, 1,  8, "%N\n"),
      @TK::TkHEREDOCEND.new(13, 3, 12, "U\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_identifier_high_unicode
    tokens = RDoc::RubyLex.tokenize '𝖒', nil

    expected = @TK::TkIDENTIFIER.new(0, 1, 0, '𝖒')

    assert_equal expected, tokens.first
  end

  def test_class_tokenize_lambda
    tokens = RDoc::RubyLex.tokenize 'a = -> x, y { x + y }', nil

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, 'a'),
      @TK::TkSPACE     .new( 1, 1,  1, ' '),
      @TK::TkASSIGN    .new( 2, 1,  2, '='),
      @TK::TkSPACE     .new( 3, 1,  3, ' '),
      @TK::TkLAMBDA    .new( 4, 1,  4, '->'),
      @TK::TkSPACE     .new( 6, 1,  6, ' '),
      @TK::TkIDENTIFIER.new( 7, 1,  7, 'x'),
      @TK::TkCOMMA     .new( 8, 1,  8, ','),
      @TK::TkSPACE     .new( 9, 1,  9, ' '),
      @TK::TkIDENTIFIER.new(10, 1, 10, 'y'),
      @TK::TkSPACE     .new(11, 1, 11, ' '),
      @TK::TkfLBRACE   .new(12, 1, 12, '{'),
      @TK::TkSPACE     .new(13, 1, 13, ' '),
      @TK::TkIDENTIFIER.new(14, 1, 14, 'x'),
      @TK::TkSPACE     .new(15, 1, 15, ' '),
      @TK::TkPLUS      .new(16, 1, 16, '+'),
      @TK::TkSPACE     .new(17, 1, 17, ' '),
      @TK::TkIDENTIFIER.new(18, 1, 18, 'y'),
      @TK::TkSPACE     .new(19, 1, 19, ' '),
      @TK::TkRBRACE    .new(20, 1, 20, '}'),
      @TK::TkNL        .new(21, 1, 21, "\n")
    ]

    assert_equal expected, tokens
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

  def test_class_tokenize_percent_r_with_slash
    tokens = RDoc::RubyLex.tokenize '%r/hi/', nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, '%r/hi/'),
      @TK::TkNL    .new( 6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_large_q
    tokens = RDoc::RubyLex.tokenize '%Q/hi/', nil

    expected = [
      @TK::TkSTRING.new( 0, 1,  0, '%Q/hi/'),
      @TK::TkNL    .new( 6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_large_q_with_double_quote
    tokens = RDoc::RubyLex.tokenize '%Q"hi"', nil

    expected = [
      @TK::TkSTRING.new( 0, 1,  0, '%Q"hi"'),
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

  def test_class_tokenize_hash_rocket
    tokens = RDoc::RubyLex.tokenize "{ :foo=> 1 }", nil

    expected = [
      @TK::TkLBRACE    .new( 0, 1,  0, '{'),
      @TK::TkSPACE     .new( 1, 1,  1, ' '),
      @TK::TkSYMBOL    .new( 2, 1,  2, ':foo'),
      @TK::TkHASHROCKET.new( 6, 1,  6, '=>'),
      @TK::TkSPACE     .new( 8, 1,  8, ' '),
      @TK::TkINTEGER   .new( 9, 1,  9, '1'),
      @TK::TkSPACE     .new(10, 1, 10, ' '),
      @TK::TkRBRACE    .new(11, 1, 11, '}'),
      @TK::TkNL        .new(12, 1, 12, "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_percent_sign_quote
    tokens = RDoc::RubyLex.tokenize '%%hi%', nil

    expected = [
      @TK::TkSTRING.new( 0, 1, 0, '%%hi%'),
      @TK::TkNL    .new( 5, 1, 5, "\n"),
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

  def test_class_tokenize_number_with_sign_character
    tokens = RDoc::RubyLex.tokenize "+3--3r", nil

    expected = [
      @TK::TkINTEGER .new(0, 1, 0, "+3"),
      @TK::TkMINUS   .new(2, 1, 2, "-"),
      @TK::TkRATIONAL.new(3, 1, 3, "-3r"),
      @TK::TkNL      .new(6, 1, 6, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_regexp_continuing_backslash
    tokens = RDoc::RubyLex.tokenize "/(?<!\\\\)\\n\z/", nil

    expected = [
      @TK::TkREGEXP.new( 0, 1,  0, "/(?<!\\\\)\\n\z/"),
      @TK::TkNL    .new(12, 1, 12, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_single_quote_escape
    tokens = RDoc::RubyLex.tokenize %q{'\\\\ \\' \\&'}, nil

    expected = [
      @TK::TkSTRING.new( 0, 1,  0, %q{'\\\\ \\' \\&'}),
      @TK::TkNL    .new(10, 1, 10, "\n"),
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

  def test_class_tokenize_string_with_escape
    tokens = RDoc::RubyLex.tokenize <<'RUBY', nil
[
  '\\',
  '\'',
  "'",
  "\'\"\`",
  "\#",
  "\#{}",
  "#",
  "#{}",
  /'"/,
  /\'\"/,
  /\//,
  /\\/,
  /\#/,
  /\#{}/,
  /#/,
  /#{}/
]
RUBY

    expected = [
      @TK::TkLBRACK .new(  0,  1,   0, "["),
      @TK::TkNL     .new(  1,  1,   1, "\n"),
      @TK::TkSPACE  .new(  2,  2,   0, "  "),
      @TK::TkSTRING .new(  4,  2,   2, "'\\\\'"),
      @TK::TkCOMMA  .new(  8,  2,   6, ","),
      @TK::TkNL     .new(  9,  2,   2, "\n"),
      @TK::TkSPACE  .new( 10,  3,   0, "  "),
      @TK::TkSTRING .new( 12,  3,   2, "'\\''"),
      @TK::TkCOMMA  .new( 16,  3,   6, ","),
      @TK::TkNL     .new( 17,  3,  10, "\n"),
      @TK::TkSPACE  .new( 18,  4,   0, "  "),
      @TK::TkSTRING .new( 20,  4,   2, "\"'\""),
      @TK::TkCOMMA  .new( 23,  4,   5, ","),
      @TK::TkNL     .new( 24,  4,  18, "\n"),
      @TK::TkSPACE  .new( 25,  5,   0, "  "),
      @TK::TkSTRING .new( 27,  5,   2, "\"\\'\\\"\\`\""),
      @TK::TkCOMMA  .new( 35,  5,  10, ","),
      @TK::TkNL     .new( 36,  5,  25, "\n"),
      @TK::TkSPACE  .new( 37,  6,   0, "  "),
      @TK::TkSTRING .new( 39,  6,   2, "\"\\#\""),
      @TK::TkCOMMA  .new( 43,  6,   6, ","),
      @TK::TkNL     .new( 44,  6,  37, "\n"),
      @TK::TkSPACE  .new( 45,  7,   0, "  "),
      @TK::TkSTRING .new( 47,  7,   2, "\"\\\#{}\""),
      @TK::TkCOMMA  .new( 53,  7,   8, ","),
      @TK::TkNL     .new( 54,  7,  45, "\n"),
      @TK::TkSPACE  .new( 55,  8,   0, "  "),
      @TK::TkSTRING .new( 57,  8,   2, "\"#\""),
      @TK::TkCOMMA  .new( 60,  8,   5, ","),
      @TK::TkNL     .new( 61,  8,  55, "\n"),
      @TK::TkSPACE  .new( 62,  9,   0, "  "),
      @TK::TkDSTRING.new( 64,  9,   2, "\"\#{}\""),
      @TK::TkCOMMA  .new( 69,  9,   7, ","),
      @TK::TkNL     .new( 70,  9,  62, "\n"),
      @TK::TkSPACE  .new( 71, 10,   0, "  "),
      @TK::TkREGEXP .new( 73, 10,   2, "/'\"/"),
      @TK::TkCOMMA  .new( 77, 10,   6, ","),
      @TK::TkNL     .new( 78, 10,  71, "\n"),
      @TK::TkSPACE  .new( 79, 11,   0, "  "),
      @TK::TkREGEXP .new( 81, 11,   2, "/\\'\\\"/"),
      @TK::TkCOMMA  .new( 87, 11,   8, ","),
      @TK::TkNL     .new( 88, 11,  79, "\n"),
      @TK::TkSPACE  .new( 89, 12,   0, "  "),
      @TK::TkREGEXP .new( 91, 12,   2, "/\\//"),
      @TK::TkCOMMA  .new( 95, 12,   6, ","),
      @TK::TkNL     .new( 96, 12,  89, "\n"),
      @TK::TkSPACE  .new( 97, 13,   0, "  "),
      @TK::TkREGEXP .new( 99, 13,   2, "/\\\\/"),
      @TK::TkCOMMA  .new(103, 13,   6, ","),
      @TK::TkNL     .new(104, 13,  97, "\n"),
      @TK::TkSPACE  .new(105, 14,   0, "  "),
      @TK::TkREGEXP .new(107, 14,   2, "/\\#/"),
      @TK::TkCOMMA  .new(111, 14,   6, ","),
      @TK::TkNL     .new(112, 14, 105, "\n"),
      @TK::TkSPACE  .new(113, 15,   0, "  "),
      @TK::TkREGEXP .new(115, 15,   2, "/\\\#{}/"),
      @TK::TkCOMMA  .new(121, 15,   8, ","),
      @TK::TkNL     .new(122, 15, 113, "\n"),
      @TK::TkSPACE  .new(123, 16,   0, "  "),
      @TK::TkREGEXP .new(125, 16,   2, "/#/"),
      @TK::TkCOMMA  .new(128, 16,   5, ","),
      @TK::TkNL     .new(129, 16, 123, "\n"),
      @TK::TkSPACE  .new(130, 17,   0, "  "),
      @TK::TkDREGEXP.new(132, 17,   2, "/\#{}/"),
      @TK::TkNL     .new(137, 17,   7, "\n"),
      @TK::TkRBRACK .new(138, 18,   0, "]"),
      @TK::TkNL     .new(139, 18, 138, "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_postfix_if_after_escaped_newline
    tokens = RDoc::RubyLex.tokenize <<'RUBY', nil
def a
  1 if true
  1 \
    if true
end
RUBY

    expected = [
      @TK::TkDEF       .new( 0, 1, 0,  "def"),
      @TK::TkSPACE     .new( 3, 1, 3,  " "),
      @TK::TkIDENTIFIER.new( 4, 1, 4,  "a"),
      @TK::TkNL        .new( 5, 1, 5,  "\n"),
      @TK::TkSPACE     .new( 6, 2, 0,  "  "),
      @TK::TkINTEGER   .new( 8, 2, 2,  "1"),
      @TK::TkSPACE     .new( 9, 2, 3,  " "),
      @TK::TkIF_MOD    .new(10, 2, 4,  "if"),
      @TK::TkSPACE     .new(12, 2, 6,  " "),
      @TK::TkTRUE      .new(13, 2, 7,  "true"),
      @TK::TkNL        .new(17, 2, 6,  "\n"),
      @TK::TkSPACE     .new(18, 3, 0,  "  "),
      @TK::TkINTEGER   .new(20, 3, 2,  "1"),
      @TK::TkSPACE     .new(21, 3, 3,  " "),
      @TK::TkBACKSLASH .new(22, 3, 4,  "\\"),
      @TK::TkNL        .new(23, 3, 18, "\n"),
      @TK::TkSPACE     .new(24, 4, 0,  "    "),
      @TK::TkIF_MOD    .new(28, 4, 4,  "if"),
      @TK::TkSPACE     .new(30, 4, 6,  " "),
      @TK::TkTRUE      .new(31, 4, 7,  "true"),
      @TK::TkNL        .new(35, 4, 24, "\n"),
      @TK::TkEND       .new(36, 5, 0,  "end"),
      @TK::TkNL        .new(39, 5, 36, "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_backtick_with_escape
    tokens = RDoc::RubyLex.tokenize <<'RUBY', nil
[
  `\\`,
  `\'\"\``,
  `\#`,
  `\#{}`,
  `#`,
  `#{}`
]
RUBY

    expected = [
      @TK::TkLBRACK  .new( 0, 1,  0, "["),
      @TK::TkNL      .new( 1, 1,  1, "\n"),
      @TK::TkSPACE   .new( 2, 2,  0, "  "),
      @TK::TkXSTRING .new( 4, 2,  2, "`\\\\`"),
      @TK::TkCOMMA   .new( 8, 2,  6, ","),
      @TK::TkNL      .new( 9, 2,  2, "\n"),
      @TK::TkSPACE   .new(10, 3,  0, "  "),
      @TK::TkXSTRING .new(12, 3,  2, "`\\'\\\"\\``"),
      @TK::TkCOMMA   .new(20, 3, 10, ","),
      @TK::TkNL      .new(21, 3, 10, "\n"),
      @TK::TkSPACE   .new(22, 4,  0, "  "),
      @TK::TkXSTRING .new(24, 4,  2, "`\\#`"),
      @TK::TkCOMMA   .new(28, 4,  6, ","),
      @TK::TkNL      .new(29, 4, 22, "\n"),
      @TK::TkSPACE   .new(30, 5,  0, "  "),
      @TK::TkXSTRING .new(32, 5,  2, "`\\\#{}`"),
      @TK::TkCOMMA   .new(38, 5,  8, ","),
      @TK::TkNL      .new(39, 5, 30, "\n"),
      @TK::TkSPACE   .new(40, 6,  0, "  "),
      @TK::TkXSTRING .new(42, 6,  2, "`#`"),
      @TK::TkCOMMA   .new(45, 6,  5, ","),
      @TK::TkNL      .new(46, 6, 40, "\n"),
      @TK::TkSPACE   .new(47, 7,  0, "  "),
      @TK::TkDXSTRING.new(49, 7,  2, "`\#{}`"),
      @TK::TkNL      .new(54, 7,  7, "\n"),
      @TK::TkRBRACK  .new(55, 8,  0, "]"),
      @TK::TkNL      .new(56, 8, 55, "\n")
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
      @TK::TkSYMBOL    .new( 6, 1,  6, 'module:'),
      @TK::TkSPACE     .new(13, 1, 13, ' '),
      @TK::TkSYMBOL    .new(14, 1, 14, ':v1'),
      @TK::TkNL        .new(17, 1, 17, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_particular_kind_of_symbols
    tokens = RDoc::RubyLex.tokenize '{ Thomas: :Thomas, Dave!: :Dave!, undef: :undef }', nil

    expected = [
      @TK::TkLBRACE.new( 0, 1,  0, "{"),
      @TK::TkSPACE .new( 1, 1,  1, " "),
      @TK::TkSYMBOL.new( 2, 1,  2, "Thomas:"),
      @TK::TkSPACE .new( 9, 1,  9, " "),
      @TK::TkSYMBOL.new(10, 1, 10, ":Thomas"),
      @TK::TkCOMMA .new(17, 1, 17, ","),
      @TK::TkSPACE .new(18, 1, 18, " "),
      @TK::TkSYMBOL.new(19, 1, 19, "Dave!:"),
      @TK::TkSPACE .new(25, 1, 25, " "),
      @TK::TkSYMBOL.new(26, 1, 26, ":Dave!"),
      @TK::TkCOMMA .new(32, 1, 32, ","),
      @TK::TkSPACE .new(33, 1, 33, " "),
      @TK::TkSYMBOL.new(34, 1, 34, "undef:"),
      @TK::TkSPACE .new(40, 1, 40, " "),
      @TK::TkSYMBOL.new(41, 1, 41, ":undef"),
      @TK::TkSPACE .new(47, 1, 47, " "),
      @TK::TkRBRACE.new(48, 1, 48, "}"),
      @TK::TkNL    .new(49, 1, 49, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_symbol_for_nested_method
    tokens = RDoc::RubyLex.tokenize 'return untrace_var :name', nil

    expected = [
      @TK::TkRETURN    .new( 0, 1,  0, "return"),
      @TK::TkSPACE     .new( 6, 1,  6, " "),
      @TK::TkIDENTIFIER.new( 7, 1,  7, "untrace_var"),
      @TK::TkSPACE     .new(18, 1, 18, " "),
      @TK::TkSYMBOL    .new(19, 1, 19, ":name"),
      @TK::TkNL        .new(24, 1, 24, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_symbol_with_quote
    tokens = RDoc::RubyLex.tokenize <<RUBY, nil
a.include?()?"a":"b"
{"t":1,'t2':2}
RUBY

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1,  0, "a"),
      @TK::TkDOT       .new( 1, 1,  1, "."),
      @TK::TkFID       .new( 2, 1,  2, "include?"),
      @TK::TkLPAREN    .new(10, 1, 10, "("),
      @TK::TkRPAREN    .new(11, 1, 11, ")"),
      @TK::TkQUESTION  .new(12, 1, 12, "?"),
      @TK::TkSTRING    .new(13, 1, 13, "\"a\""),
      @TK::TkCOLON     .new(16, 1, 16, ":"),
      @TK::TkSTRING    .new(17, 1, 17, "\"b\""),
      @TK::TkNL        .new(20, 1, 20, "\n"),
      @TK::TkLBRACE    .new(21, 2,  0, "{"),
      @TK::TkSYMBOL    .new(22, 2,  1, "\"t\":"),
      @TK::TkINTEGER   .new(26, 2,  5, "1"),
      @TK::TkCOMMA     .new(27, 2,  6, ","),
      @TK::TkSYMBOL    .new(28, 2,  7, "'t2':"),
      @TK::TkINTEGER   .new(33, 2, 12, "2"),
      @TK::TkRBRACE    .new(34, 2, 13, "}"),
      @TK::TkNL        .new(35, 2, 21, "\n"),
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

  def test_rational_imaginary_tokenize
    tokens = RDoc::RubyLex.tokenize '1.11r + 2.34i + 5.55ri + 0i', nil

    expected = [
      @TK::TkRATIONAL .new( 0, 1,  0, '1.11r'),
      @TK::TkSPACE    .new( 5, 1,  5, ' '),
      @TK::TkPLUS     .new( 6, 1,  6, '+'),
      @TK::TkSPACE    .new( 7, 1,  7, ' '),
      @TK::TkIMAGINARY.new( 8, 1,  8, '2.34i'),
      @TK::TkSPACE    .new(13, 1, 13, ' '),
      @TK::TkPLUS     .new(14, 1, 14, '+'),
      @TK::TkSPACE    .new(15, 1, 15, ' '),
      @TK::TkIMAGINARY.new(16, 1, 16, '5.55ri'),
      @TK::TkSPACE    .new(22, 1, 22, ' '),
      @TK::TkPLUS     .new(23, 1, 23, '+'),
      @TK::TkSPACE    .new(24, 1, 24, ' '),
      @TK::TkIMAGINARY.new(25, 1, 25, '0i'),
      @TK::TkNL       .new(27, 1, 27, "\n"),
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_square_bracket_as_method
    tokens = RDoc::RubyLex.tokenize "Array.[](1, 2)", nil

    expected = [
      @TK::TkCONSTANT  .new(0,  1,  0, "Array"),
      @TK::TkDOT       .new(5,  1,  5, "."),
      @TK::TkIDENTIFIER.new(6,  1,  6, "[]"),
      @TK::TkfLPAREN   .new(8,  1,  8, "("),
      @TK::TkINTEGER   .new(9,  1,  9, "1"),
      @TK::TkCOMMA     .new(10, 1, 10, ","),
      @TK::TkSPACE     .new(11, 1, 11, " "),
      @TK::TkINTEGER   .new(12, 1, 12, "2"),
      @TK::TkRPAREN    .new(13, 1, 13, ")"),
      @TK::TkNL        .new(14, 1, 14, "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_constant_with_exclamation
    tokens = RDoc::RubyLex.tokenize "Hello there, Dave!", nil

    expected = [
      @TK::TkCONSTANT  .new( 0, 1,  0, "Hello"),
      @TK::TkSPACE     .new( 5, 1,  5, " "),
      @TK::TkIDENTIFIER.new( 6, 1,  6, "there"),
      @TK::TkCOMMA     .new(11, 1, 11, ","),
      @TK::TkSPACE     .new(12, 1, 12, " "),
      @TK::TkIDENTIFIER.new(13, 1, 13, "Dave!"),
      @TK::TkNL        .new(18, 1, 18, "\n")
    ]

    assert_equal expected, tokens
  end

  def test_class_tokenize_identifer_not_equal
    tokens = RDoc::RubyLex.tokenize "foo!=bar\nfoo?=bar", nil

    expected = [
      @TK::TkIDENTIFIER.new( 0, 1, 0, "foo"),
      @TK::TkNEQ       .new( 3, 1, 3, "!="),
      @TK::TkIDENTIFIER.new( 5, 1, 5, "bar"),
      @TK::TkNL        .new( 8, 1, 8, "\n"),
      @TK::TkFID       .new( 9, 2, 0, "foo?"),
      @TK::TkASSIGN    .new(13, 2, 4, "="),
      @TK::TkIDENTIFIER.new(14, 2, 5, "bar"),
      @TK::TkNL        .new(17, 2, 9, "\n"),
    ]

    assert_equal expected, tokens
  end

end

