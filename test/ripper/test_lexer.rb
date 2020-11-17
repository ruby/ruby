# frozen_string_literal: true
begin
  require 'ripper'
  require 'test/unit'
  module TestRipper; end
rescue LoadError
end

class TestRipper::Lexer < Test::Unit::TestCase
  def test_nested_dedent_heredoc
    bug = '[ruby-core:80977] [Bug #13536]'
    str = <<~'E'
    <<~"D"
    #{
    <<~"B"
    this must be a valid ruby
    B
    }
    D
    E
    assert_equal(str, Ripper.tokenize(str).join(""), bug)

    str = <<~'E'
    <<~"D"
    #{
    <<~"B"
      this must be a valid ruby
    B
    }
    D
    E
    assert_equal(str, Ripper.tokenize(str).join(""), bug)
  end

  def test_embedded_expr_in_heredoc
    src = <<~'E'
    <<~B
      #{1}
    B
    E
    expect = %I[
      on_heredoc_beg
      on_nl
      on_ignored_sp
      on_embexpr_beg
      on_int
      on_embexpr_end
      on_tstring_content
      on_heredoc_end
    ]
    assert_equal expect, Ripper.lex(src).map {|e| e[1]}
  end

  def test_space_after_expr_in_heredoc
    src = <<~'E'
    <<~B
     #{1} a
    B
    E
    expect = %I[
      on_heredoc_beg
      on_nl
      on_ignored_sp
      on_embexpr_beg
      on_int
      on_embexpr_end
      on_tstring_content
      on_heredoc_end
    ]
    assert_equal expect, Ripper.lex(src).map {|e| e[1]}
  end

  def test_expr_at_beginning_in_heredoc
    src = <<~'E'
    <<~B
      a
    #{1}
    B
    E
    expect = %I[
      on_heredoc_beg
      on_nl
      on_tstring_content
      on_embexpr_beg
      on_int
      on_embexpr_end
      on_tstring_content
      on_heredoc_end
    ]
    assert_equal expect, Ripper.lex(src).map {|e| e[1]}
  end

  def test_slice
    assert_equal "string\#{nil}\n",
      Ripper.slice(%(<<HERE\nstring\#{nil}\nHERE), "heredoc_beg .*? nl $(.*?) heredoc_end", 1)
  end

  def state(name)
    Ripper::Lexer::State.new(Ripper.const_get(name))
  end

  def test_state_after_ivar
    assert_equal [[1,0],:on_ivar,"@a",state(:EXPR_END)], Ripper.lex("@a").last
    assert_equal [[1,1],:on_ivar,"@a",state(:EXPR_ENDFN)], Ripper.lex(":@a").last
    assert_equal [[1,1],:on_int,"1",state(:EXPR_END)], Ripper.lex("@1").last
    assert_equal [[1,2],:on_int,"1",state(:EXPR_END)], Ripper.lex(":@1").last
  end

  def test_state_after_cvar
    assert_equal [[1,0],:on_cvar,"@@a",state(:EXPR_END)], Ripper.lex("@@a").last
    assert_equal [[1,1],:on_cvar,"@@a",state(:EXPR_ENDFN)], Ripper.lex(":@@a").last
    assert_equal [[1,2],:on_int,"1",state(:EXPR_END)], Ripper.lex("@@1").last
    assert_equal [[1,3],:on_int,"1",state(:EXPR_END)], Ripper.lex(":@@1").last
  end

  def test_token_aftr_error_heredoc
    code = "<<A.upcase\n"
    result = Ripper::Lexer.new(code).scan
    message = proc {result.pretty_inspect}
    expected = [
      [[1, 0], :on_heredoc_beg, "<<A", state(:EXPR_BEG)],
      [[1, 2], :compile_error, "A", state(:EXPR_BEG), "can't find string \"A\" anywhere before EOF"],
      [[1, 3], :on_period, ".", state(:EXPR_DOT)],
      [[1, 4], :on_ident, "upcase", state(:EXPR_ARG)],
      [[1, 10], :on_nl, "\n", state(:EXPR_BEG)],
    ]
    pos = 0
    expected.each_with_index do |ex, i|
      s = result[i]
      assert_equal ex, s.to_a, message
      if pos > s.pos[1]
        assert_equal pos, s.pos[1] + s.tok.bytesize, message
      else
        assert_equal pos, s.pos[1], message
        pos += s.tok.bytesize
      end
    end
    assert_equal pos, code.bytesize
    assert_equal expected.size, result.size
  end

  def test_trailing_on_embexpr_end
    # This is useful for scanning a template engine literal `{ foo, bar: baz }`
    # whose body inside brackes works like trailing method arguments, like Haml.
    token = Ripper.lex("a( foo, bar: baz }").last
    assert_equal [[1, 17], :on_embexpr_end, "}", state(:EXPR_ARG)], token
  end

  def test_raise_errors_keyword
    assert_raise(SyntaxError) { Ripper.tokenize('def req(true) end', raise_errors: true) }
    assert_raise(SyntaxError) { Ripper.tokenize('def req(true) end', raise_errors: true) }
  end
end
