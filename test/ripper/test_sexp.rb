# frozen_string_literal: false
begin
  require 'ripper'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Sexp < Test::Unit::TestCase
  def test_compile_error
    assert_nil Ripper.sexp("/")
    assert_nil Ripper.sexp("-")
    assert_nil Ripper.sexp("+")
    assert_nil Ripper.sexp("*")
    assert_nil Ripper.sexp("end")
    assert_nil Ripper.sexp("end 1")
    assert_nil Ripper.sexp("/*")
    assert_nil Ripper.sexp("/*/")
    assert_nil Ripper.sexp("/+/")
  end

  def test_regexp_content
    sexp = Ripper.sexp('//')
    assert_nil search_sexp(:@tstring_content, search_sexp(:regexp_literal, sexp))

    sexp = Ripper.sexp('/foo/')
    assert_equal 'foo', search_sexp(:@tstring_content, search_sexp(:regexp_literal, sexp))[1]

    sexp = Ripper.sexp("/foo\nbar/")
    assert_equal "foo\nbar", search_sexp(:@tstring_content, search_sexp(:regexp_literal, sexp))[1]

    sexp = Ripper.sexp('/(?<n>a(b|\g<n>))/')
    assert_equal '(?<n>a(b|\g<n>))', search_sexp(:@tstring_content, search_sexp(:regexp_literal, sexp))[1]
  end

  def test_heredoc_content
    sexp = Ripper.sexp("<<E\nfoo\nE")
    assert_equal "foo\n", search_sexp(:@tstring_content, sexp)[1]
  end

  def test_squiggly_heredoc
    sexp = Ripper.sexp("<<~eot\n      asdf\neot")
    assert_equal "asdf\n", search_sexp(:@tstring_content, sexp)[1]
  end

  def test_squiggly_heredoc_with_interpolated_expression
    sexp1 = Ripper.sexp(<<-eos)
<<-eot
a\#{1}z
eot
    eos

    sexp2 = Ripper.sexp(<<-eos)
<<~eot
  a\#{1}z
eot
    eos

    assert_equal clear_pos(sexp1), clear_pos(sexp2)
  end

  def search_sexp(sym, sexp)
    return sexp if !sexp or sexp[0] == sym
    sexp.find do |e|
      if Array === e and e = search_sexp(sym, e)
        return e
      end
    end
  end

  def clear_pos(sexp)
    return sexp if !sexp
    sexp.each do |e|
      if Array === e
        if e.size == 3 and Array === (last = e.last) and
          last.size == 2 and Integer === last[0] and Integer === last[1]
          last.clear
        else
          clear_pos(e)
        end
      end
    end
  end
end if ripper_test
