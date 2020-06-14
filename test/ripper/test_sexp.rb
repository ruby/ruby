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

  pattern_matching_data = {
    [__LINE__, %q{ case 0; in 0; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:@int, "0", [1, 11]], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in 0 if a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:if_mod, [:vcall, [:@ident, "a", [1, 16]]], [:@int, "0", [1, 11]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in 0 unless a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:unless_mod, [:vcall, [:@ident, "a", [1, 20]]], [:@int, "0", [1, 11]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:var_field, [:@ident, "a", [1, 11]]], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in a,; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          nil,
          [[:var_field, [:@ident, "a", [1, 11]]]],
          [:var_field, nil],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in a,b; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          nil,
          [[:var_field, [:@ident, "a", [1, 11]]],
            [:var_field, [:@ident, "b", [1, 13]]]],
          nil,
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in *a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn, nil, nil, [:var_field, [:@ident, "a", [1, 12]]], nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in *a,b; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          nil,
          nil,
          [:var_field, [:@ident, "a", [1, 12]]],
          [[:var_field, [:@ident, "b", [1, 14]]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in *a,b,c; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          nil,
          nil,
          [:var_field, [:@ident, "a", [1, 12]]],
          [[:var_field, [:@ident, "b", [1, 14]]],
            [:var_field, [:@ident, "c", [1, 16]]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in *; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:aryptn, nil, nil, [:var_field, nil], nil], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in *,a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          nil,
          nil,
          [:var_field, nil],
          [[:var_field, [:@ident, "a", [1, 13]]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in a:,**b; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          nil,
          [[[:@label, "a:", [1, 11]], nil]],
          [:var_field, [:@ident, "b", [1, 16]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in **a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn, nil, [], [:var_field, [:@ident, "a", [1, 13]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in **; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:hshptn, nil, [], nil], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in a: 0; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn, nil, [[[:@label, "a:", [1, 11]], [:@int, "0", [1, 14]]]], nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in a:; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn, nil, [[[:@label, "a:", [1, 11]], nil]], nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in "a": 0; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          nil,
          [[[:string_content, [:@tstring_content, "a", [1, 12]]],
              [:@int, "0", [1, 16]]]],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in "a":; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          nil,
          [[[:string_content, [:@tstring_content, "a", [1, 12]]], nil]],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in a: 0, b: 0; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          nil,
          [[[:@label, "a:", [1, 11]], [:@int, "0", [1, 14]]],
            [[:@label, "b:", [1, 17]], [:@int, "0", [1, 20]]]],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in 0 => a; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:binary,
          [:@int, "0", [1, 11]],
          :"=>",
          [:var_field, [:@ident, "a", [1, 16]]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in 0 | 1; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:binary, [:@int, "0", [1, 11]], :|, [:@int, "1", [1, 15]]],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A(0); end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          [:var_ref, [:@const, "A", [1, 11]]],
          [[:@int, "0", [1, 13]]],
          nil,
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A(a:); end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          [:var_ref, [:@const, "A", [1, 11]]],
          [[[:@label, "a:", [1, 13]], nil]],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A(); end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn, [:var_ref, [:@const, "A", [1, 11]]], nil, nil, nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A[a]; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn,
          [:var_ref, [:@const, "A", [1, 11]]],
          [[:var_field, [:@ident, "a", [1, 13]]]],
          nil,
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A[a:]; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn,
          [:var_ref, [:@const, "A", [1, 11]]],
          [[[:@label, "a:", [1, 13]], nil]],
          nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in A[]; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn, [:var_ref, [:@const, "A", [1, 11]]], nil, nil, nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in [a]; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:aryptn, nil, [[:var_field, [:@ident, "a", [1, 12]]]], nil, nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in []; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:aryptn, nil, nil, nil, nil], [[:void_stmt]], nil]],

    [__LINE__, %q{ 0 in [*, a, *] }] =>
    [:case,
      [:@int, "0", [1, 0]],
      [:in,
        [:fndptn,
          nil,
          [:var_field, nil],
          [[:var_field, [:@ident, "a", [1, 9]]]],
          [:var_field, nil]],
        nil,
        nil]],

    [__LINE__, %q{ 0 in [*a, b, *c] }] =>
    [:case,
      [:@int, "0", [1, 0]],
      [:in,
        [:fndptn,
          nil,
          [:var_field, [:@ident, "a", [1, 7]]],
          [[:var_field, [:@ident, "b", [1, 10]]]],
          [:var_field, [:@ident, "c", [1, 14]]]],
        nil,
        nil]],

    [__LINE__, %q{ 0 in A(*a, b, c, *d) }] =>
    [:case,
      [:@int, "0", [1, 0]],
      [:in,
        [:fndptn,
          [:var_ref, [:@const, "A", [1, 5]]],
          [:var_field, [:@ident, "a", [1, 8]]],
          [[:var_field, [:@ident, "b", [1, 11]]],
            [:var_field, [:@ident, "c", [1, 14]]]],
          [:var_field, [:@ident, "d", [1, 18]]]],
        nil,
        nil]],

    [__LINE__, %q{ case 0; in {a: 0}; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in,
        [:hshptn, nil, [[[:@label, "a:", [1, 12]], [:@int, "0", [1, 15]]]], nil],
        [[:void_stmt]],
        nil]],

    [__LINE__, %q{ case 0; in {}; end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:hshptn, nil, nil, nil], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in (0); end }] =>
    [:case,
      [:@int, "0", [1, 5]],
      [:in, [:@int, "0", [1, 12]], [[:void_stmt]], nil]],

    [__LINE__, %q{ case 0; in a:, a:; end }] =>
    nil,

    [__LINE__, %q{ case 0; in a?:; end }] =>
    nil,

    [__LINE__, %q{ case 0; in "A":; end }] =>
    nil,

    [__LINE__, %q{ case 0; in "a\x0":a1, "a\0":a2; end }] =>
    nil,                        # duplicated key name
  }
  pattern_matching_data.each do |(i, src), expected|
    define_method(:"test_pattern_matching_#{i}") do
      sexp = Ripper.sexp(src.strip)
      assert_equal expected, sexp && sexp[1][0], src
    end
  end

  def test_hshptn
    parser = Class.new(Ripper::SexpBuilder) do
      def on_label(token)
        [:@label, token]
      end
    end

    result = parser.new("#{<<~"begin;"}#{<<~'end;'}").parse
    begin;
      case foo
      in { a: 1 }
        bar
      else
        baz
      end
    end;

    hshptn = result.dig(1, 2, 2, 1)
    assert_equal(:hshptn, hshptn[0])
    assert_equal([:@label, "a:"], hshptn.dig(2, 0, 0))
  end
end if ripper_test
