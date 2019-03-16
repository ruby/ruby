# frozen_string_literal: true
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

  def test_params_mlhs
    sexp = Ripper.sexp("proc {|(w, *x, y), z|}")
    _, ((mlhs, w, (rest, x), y), z) = search_sexp(:params, sexp)
    assert_equal(:mlhs, mlhs)
    assert_equal(:@ident, w[0])
    assert_equal("w", w[1])
    assert_equal(:rest_param, rest)
    assert_equal(:@ident, x[0])
    assert_equal("x", x[1])
    assert_equal(:@ident, y[0])
    assert_equal("y", y[1])
    assert_equal(:@ident, z[0])
    assert_equal("z", z[1])
  end

  def test_def_fname
    sexp = Ripper.sexp("def t; end")
    _, (type, fname,) = search_sexp(:def, sexp)
    assert_equal(:@ident, type)
    assert_equal("t", fname)

    sexp = Ripper.sexp("def <<; end")
    _, (type, fname,) = search_sexp(:def, sexp)
    assert_equal(:@op, type)
    assert_equal("<<", fname)
  end

  def test_defs_fname
    sexp = Ripper.sexp("def self.t; end")
    _, recv, _, (type, fname) = search_sexp(:defs, sexp)
    assert_equal(:var_ref, recv[0], recv)
    assert_equal([:@kw, "self", [1, 4]], recv[1], recv)
    assert_equal(:@ident, type)
    assert_equal("t", fname)
  end

  def test_named_with_default
    sexp = Ripper.sexp("def hello(bln: true, int: 1, str: 'str', sym: :sym) end")
    named = String.new
    search_sexp(:params, sexp)[5].each { |i| named << "#{i}\n" }  # join flattens
    exp = "#{<<-"{#"}#{<<~'};'}"
    {#
      [[:@label, "bln:", [1, 10]], [:var_ref, [:@kw, "true", [1, 15]]]]
      [[:@label, "int:", [1, 21]], [:@int, "1", [1, 26]]]
      [[:@label, "str:", [1, 29]], [:string_literal, [:string_content, [:@tstring_content, "str", [1, 35]]]]]
      [[:@label, "sym:", [1, 41]], [:symbol_literal, [:symbol, [:@ident, "sym", [1, 47]]]]]
    };
    assert_equal(exp, named)
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

  def test_dsym
    bug15670 = '[ruby-core:91852]'
    _, (_, _, s) = Ripper.sexp_raw(%q{:"sym"})
    assert_equal([:dyna_symbol, [:string_add, [:string_content], [:@tstring_content, "sym", [1, 2]]]],
                 s,
                 bug15670)
  end
end if ripper_test
