# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'stringio'

class TestParse < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_error_line
    assert_syntax_error('------,,', /\n\z/, 'Message to pipe should end with a newline')
  end

  def test_else_without_rescue
    assert_syntax_error(<<-END, %r":#{__LINE__+2}: else without rescue"o, [__FILE__, __LINE__+1])
      begin
      else
        42
      end
    END
  end

  def test_alias_backref
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        alias $foo $1
      END
    end
  end

  def test_command_call
    t = Object.new
    def t.foo(x); x; end

    a = false
    b = c = d = true
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a &&= t.foo 42
        b &&= t.foo 42
        c &&= t.foo nil
        d &&= t.foo false
      END
    end
    assert_equal([false, 42, nil, false], [a, b, c, d])

    a = 3
    assert_nothing_raised { eval("a &= t.foo 5") }
    assert_equal(1, a)

    a = [nil, nil, true, true]
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a[0] ||= t.foo 42
        a[1] &&= t.foo 42
        a[2] ||= t.foo 42
        a[3] &&= t.foo 42
      END
    end
    assert_equal([42, nil, true, 42], a)

    o = Object.new
    class << o
      attr_accessor :foo, :bar, :Foo, :Bar, :baz, :qux
    end
    o.foo = o.Foo = o::baz = nil
    o.bar = o.Bar = o::qux = 1
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo ||= t.foo 42
        o.bar &&= t.foo 42
        o.Foo ||= t.foo 42
        o.Bar &&= t.foo 42
        o::baz ||= t.foo 42
        o::qux &&= t.foo 42
      END
    end
    assert_equal([42, 42], [o.foo, o.bar])
    assert_equal([42, 42], [o.Foo, o.Bar])
    assert_equal([42, 42], [o::baz, o::qux])

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        $1 ||= t.foo 42
      END
    end

    def t.bar(x); x + yield; end

    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t.bar "foo" do
          "bar"
        end.gsub "ob", "OB"
        b = t.bar "foo" do
          "bar"
        end::gsub "ob", "OB"
      END
    end
    assert_equal("foOBar", a)
    assert_equal("foOBar", b)

    a = nil
    assert_nothing_raised do
      t.instance_eval <<-END, __FILE__, __LINE__+1
        a = bar "foo" do "bar" end
      END
    end
    assert_equal("foobar", a)

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t::bar "foo" do "bar" end
      END
    end
    assert_equal("foobar", a)

    def t.baz(*r)
      @baz = r + (block_given? ? [yield] : [])
    end

    assert_nothing_raised do
      t.instance_eval "baz (1), 2"
    end
    assert_equal([1, 2], t.instance_eval { @baz })
  end

  def test_mlhs_node
    c = Class.new
    class << c
      attr_accessor :foo, :bar, :Foo, :Bar
      FOO = BAR = nil
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        c::foo, c::bar = 1, 2
        c.Foo, c.Bar = 1, 2
        c::FOO, c::BAR = 1, 2
      END
    end
    assert_equal([1, 2], [c::foo, c::bar])
    assert_equal([1, 2], [c.Foo, c.Bar])
    assert_equal([1, 2], [c::FOO, c::BAR])
  end

  def test_dynamic_constant_assignment
    assert_raise(SyntaxError) do
      Object.new.instance_eval <<-END, __FILE__, __LINE__+1
        def foo
          self::FOO, self::BAR = 1, 2
          ::FOO, ::BAR = 1, 2
        end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        $1, $2 = 1, 2
      END
    end

    assert_raise(SyntaxError) do
      Object.new.instance_eval <<-END, __FILE__, __LINE__+1
        def foo
          ::FOO = 1
        end
      END
    end

    c = Class.new
    c.freeze
    assert_nothing_raised(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
      if false
        c::FOO &= 1
        ::FOO &= 1
      end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        $1 &= 1
      END
    end
  end

  def test_class_module
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        class foo; end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo
          class Foo; end
          module Bar; end
        end
      END
    end

    assert_nothing_raised(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        class Foo 1; end
      END
    end
  end

  def test_op_name
    o = Object.new
    def o.>(x); x; end
    def o./(x); x; end

    assert_nothing_raised do
      o.instance_eval <<-END, __FILE__, __LINE__+1
        undef >, /
      END
    end
  end

  def test_arg
    o = Object.new
    class << o
      attr_accessor :foo, :bar, :Foo, :Bar, :baz, :qux
    end
    o.foo = o.Foo = o::baz = nil
    o.bar = o.Bar = o::qux = 1
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo ||= 42
        o.bar &&= 42
        o.Foo ||= 42
        o.Bar &&= 42
        o::baz ||= 42
        o::qux &&= 42
      END
    end
    assert_equal([42, 42], [o.foo, o.bar])
    assert_equal([42, 42], [o.Foo, o.Bar])
    assert_equal([42, 42], [o::baz, o::qux])

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = -2.0 ** 2
      END
    end
    assert_equal(-4.0, a)
  end

  def test_block_variable
    o = Object.new
    def o.foo(*r); yield(*r); end

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo 1 do|; a| a = 42 end
      END
    end
    assert_nil(a)
  end

  def test_bad_arg
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo(FOO); end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo(@foo); end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo($foo); end
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo(@@foo); end
      END
    end

    o = Object.new
    def o.foo(*r); yield(*r); end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo 1 {|; @a| @a = 42 }
      END
    end
  end

  def test_do_lambda
    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = -> do
          b = 42
        end
      END
    end
    a.call
    assert_equal(42, b)
  end

  def test_block_call_colon2
    o = Object.new
    def o.foo(x); x + yield; end

    a = b = nil
    assert_nothing_raised do
      o.instance_eval <<-END, __FILE__, __LINE__+1
        a = foo 1 do 42 end.to_s
        b = foo 1 do 42 end::to_s
      END
    end
    assert_equal("43", a)
    assert_equal("43", b)
  end

  def test_call_method
    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = proc {|x| x + "bar" }.("foo")
        b = proc {|x| x + "bar" }::("foo")
      END
    end
    assert_equal("foobar", a)
    assert_equal("foobar", b)
  end

  def test_xstring
    assert_raise(Errno::ENOENT) do
      eval("``")
    end
  end

  def test_words
    assert_equal([], %W( ))
    assert_syntax_error('%w[abc', /unterminated list/)
  end

  def test_dstr
    @@foo = 1
    assert_equal("foo 1 bar", "foo #@@foo bar")
    "1" =~ /(.)/
    assert_equal("foo 1 bar", "foo #$1 bar")
  end

  def test_dstr_disallowed_variable
    bug8375 = '[ruby-core:54885] [Bug #8375]'
    %w[@ @. @@ @@1 @@. $ $%].each do |src|
      src = '#'+src+' '
      str = assert_nothing_raised(SyntaxError, "#{bug8375} #{src.dump}") do
        break eval('"'+src+'"')
      end
      assert_equal(src, str, bug8375)
    end
  end

  def test_dsym
    assert_nothing_raised { eval(':""') }
  end

  def assert_disallowed_variable(type, noname, invalid)
    noname.each do |name|
      assert_syntax_error("proc{a = #{name} }", "`#{noname[0]}' without identifiers is not allowed as #{type} variable name")
    end
    invalid.each do |name|
      assert_syntax_error("proc {a = #{name} }", "`#{name}' is not allowed as #{type} variable name")
    end
  end

  def test_disallowed_instance_variable
    assert_disallowed_variable("an instance", %w[@ @.], %w[])
  end

  def test_disallowed_class_variable
    assert_disallowed_variable("a class", %w[@@ @@.], %w[@@1])
  end

  def test_disallowed_gloal_variable
    assert_disallowed_variable("a global", %w[$], %w[$%])
  end

  def test_arg2
    o = Object.new

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(a=42,*r,z,&b); b.call(r.inject(a*1000+z*100, :+)); end
      END
    end
    assert_equal(-1405, o.foo(1,2,3,4) {|x| -x })
    assert_equal(-1302, o.foo(1,2,3) {|x| -x })
    assert_equal(-1200, o.foo(1,2) {|x| -x })
    assert_equal(-42100, o.foo(1) {|x| -x })
    assert_raise(ArgumentError) { o.foo() }

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(a=42,z,&b); b.call(a*1000+z*100); end
      END
    end
    assert_equal(-1200, o.foo(1,2) {|x| -x } )
    assert_equal(-42100, o.foo(1) {|x| -x } )
    assert_raise(ArgumentError) { o.foo() }

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(*r,z,&b); b.call(r.inject(z*100, :+)); end
      END
    end
    assert_equal(-303, o.foo(1,2,3) {|x| -x } )
    assert_equal(-201, o.foo(1,2) {|x| -x } )
    assert_equal(-100, o.foo(1) {|x| -x } )
    assert_raise(ArgumentError) { o.foo() }
  end

  def test_duplicate_argument
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        1.times {|&b?| }
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        1.times {|a, a|}
      END
    end

    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo(a, a); end
      END
    end
  end

  def test_define_singleton_error
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def ("foo").foo; end
      END
    end
  end

  def test_op_asgn1_with_block
    t = Object.new
    a = []
    blk = proc {|x| a << x }
    def t.[](_)
      yield(:aref)
      nil
    end
    def t.[]=(_, _)
      yield(:aset)
    end
    def t.dummy(_)
    end
    eval <<-END, nil, __FILE__, __LINE__+1
      t[42, &blk] ||= 42
    END
    assert_equal([:aref, :aset], a)
    a.clear
    eval <<-END, nil, __FILE__, __LINE__+1
    t[42, &blk] ||= t.dummy 42 # command_asgn test
    END
    assert_equal([:aref, :aset], a)
    blk
  end

  def test_backquote
    t = Object.new

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def t.`(x); "foo" + x + "bar"; end
      END
    end
    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t.` "zzz"
        1.times {|;z| t.` ("zzz") }
      END
      t.instance_eval <<-END, __FILE__, __LINE__+1
        b = `zzz`
      END
    end
    assert_equal("foozzzbar", a)
    assert_equal("foozzzbar", b)
  end

  def test_carrige_return
    assert_equal(2, eval("1 +\r\n1"))
  end

  def test_string
    mesg = 'from the backslash through the invalid char'

    e = assert_syntax_error('"\xg1"', /hex escape/)
    assert_equal(' ^~'"\n", e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{1234"', 'unterminated Unicode escape')
    assert_equal('        ^'"\n", e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{xxxx}"', 'invalid Unicode escape')
    assert_equal('    ^'"\n", e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{xxxx', 'Unicode escape')
    assert_pattern_list([
                          /.*: invalid Unicode escape\n.*\n/,
                          /    \^/,
                          /\n/,
                          /.*: unterminated Unicode escape\n.*\n/,
                          /    \^/,
                          /\n/,
                          /.*: unterminated string.*\n.*\n/,
                          /        \^\n/,
                        ], e.message)

    e = assert_syntax_error('"\M1"', /escape character syntax/)
    assert_equal(' ^~~'"\n", e.message.lines.last, mesg)

    e = assert_syntax_error('"\C1"', /escape character syntax/)
    assert_equal(' ^~~'"\n", e.message.lines.last, mesg)

    src = '"\xD0\u{90'"\n""000000000000000000000000"
    assert_syntax_error(src, /:#{__LINE__}: unterminated/o)

    assert_syntax_error('"\u{100000000}"', /invalid Unicode escape/)
    assert_equal("", eval('"\u{}"'))
    assert_equal("", eval('"\u{ }"'))

    assert_equal("\x81", eval('"\C-\M-a"'))
    assert_equal("\177", eval('"\c?"'))

    assert_warning(/use \\C-\\s/) {assert_equal("\x00", eval('"\C- "'))}
    assert_warning(/use \\M-\\s/) {assert_equal("\xa0", eval('"\M- "'))}
    assert_warning(/use \\M-\\C-\\s/) {assert_equal("\x80", eval('"\M-\C- "'))}
    assert_warning(/use \\C-\\M-\\s/) {assert_equal("\x80", eval('"\C-\M- "'))}
    assert_warning(/use \\t/) {assert_equal("\x09", eval("\"\\C-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\M-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\M-\\C-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\C-\\M-\t\""))}
    assert_syntax_error("\"\\C-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\M-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\M-\\C-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\C-\\M-\x01\"", 'Invalid escape character syntax')
  end

  def test_question
    assert_raise(SyntaxError) { eval('?') }
    assert_raise(SyntaxError) { eval('? ') }
    assert_raise(SyntaxError) { eval("?\n") }
    assert_raise(SyntaxError) { eval("?\t") }
    assert_raise(SyntaxError) { eval("?\v") }
    assert_raise(SyntaxError) { eval("?\r") }
    assert_raise(SyntaxError) { eval("?\f") }
    assert_raise(SyntaxError) { eval("?\f") }
    assert_raise(SyntaxError) { eval(" ?a\x8a".force_encoding("utf-8")) }
    assert_equal("\u{1234}", eval("?\u{1234}"))
    assert_equal("\u{1234}", eval('?\u{1234}'))
    assert_equal("\u{1234}", eval('?\u1234'))
    assert_syntax_error('?\u{41 42}', 'Multiple codepoints at single character literal')
    e = assert_syntax_error('"#{?\u123}"', 'invalid Unicode escape')
    assert_not_match(/end-of-input/, e.message)

    assert_warning(/use ?\\C-\\s/) {assert_equal("\x00", eval('?\C- '))}
    assert_warning(/use ?\\M-\\s/) {assert_equal("\xa0", eval('?\M- '))}
    assert_warning(/use ?\\M-\\C-\\s/) {assert_equal("\x80", eval('?\M-\C- '))}
    assert_warning(/use ?\\C-\\M-\\s/) {assert_equal("\x80", eval('?\C-\M- '))}
    assert_warning(/use ?\\t/) {assert_equal("\x09", eval("?\\C-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\M-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\M-\\C-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\C-\\M-\t"))}
    assert_syntax_error("?\\C-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\M-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\M-\\C-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\C-\\M-\x01", 'Invalid escape character syntax')
  end

  def test_percent
    assert_equal(:foo, eval('%s(foo)'))
    assert_raise(SyntaxError) { eval('%s') }
    assert_raise(SyntaxError) { eval('%ss') }
    assert_raise(SyntaxError) { eval('%z()') }
  end

  def test_symbol
    bug = '[ruby-dev:41447]'
    sym = "foo\0bar".to_sym
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(":'foo\0bar'"))
    end
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(':"foo\u0000bar"'))
    end
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(':"foo\u{0}bar"'))
    end
    assert_nothing_raised(SyntaxError) do
      assert_equal(:foobar, eval(':"foo\u{}bar"'))
      assert_equal(:foobar, eval(':"foo\u{ }bar"'))
    end

    assert_syntax_error(':@@', /is not allowed/)
    assert_syntax_error(':@@1', /is not allowed/)
    assert_syntax_error(':@', /is not allowed/)
    assert_syntax_error(':@1', /is not allowed/)
  end

  def test_parse_string
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
/
      END
    end
  end

  def test_here_document
    x = nil

    assert_raise(SyntaxError) do
      eval %Q(
<\<FOO
      )
    end

    assert_nothing_raised(SyntaxError) do
      x = eval %q(
<<FOO
#$
FOO
      )
    end
    assert_equal "\#$\n", x

    assert_raise(SyntaxError) do
      eval %Q(
<\<\"
      )
    end

    assert_raise(SyntaxError) do
      eval %q(
<<``
      )
    end

    assert_raise(SyntaxError) do
      eval %q(
<<--
      )
    end

    assert_nothing_raised(SyntaxError) do
      x = eval %q(
<<FOO
#$
foo
FOO
      )
    end
    assert_equal "\#$\nfoo\n", x

    assert_nothing_raised do
      eval "x = <<""FOO\r\n1\r\nFOO"
    end
    assert_equal("1\n", x)
  end

  def test_magic_comment
    x = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = utf-8
x = __ENCODING__
      END
    end
    assert_equal(Encoding.find("UTF-8"), x)

    assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = foobarbazquxquux_dummy_enconding
x = __ENCODING__
      END
    end
  end

  def test_utf8_bom
    x = nil
    assert_nothing_raised do
      eval "\xef\xbb\xbf x = __ENCODING__"
    end
    assert_equal(Encoding.find("UTF-8"), x)
    assert_raise(NameError) { eval "\xef" }
  end

  def test_dot_in_next_line
    x = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        x = 1
        .to_s
      END
    end
    assert_equal("1", x)
  end

  def test_pow_asgn
    x = 3
    assert_nothing_raised { eval("x **= 2") }
    assert_equal(9, x)
  end

  def test_embedded_rd
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
=begin
      END
    end
  end

  def test_float
    assert_equal(1.0/0, eval("1e10000"))
    assert_raise(SyntaxError) { eval('1_E') }
    assert_raise(SyntaxError) { eval('1E1E1') }
  end

  def test_global_variable
    assert_equal(nil, eval('$-x'))
    assert_equal(nil, eval('alias $preserve_last_match $&'))
    assert_equal(nil, eval('alias $& $test_parse_foobarbazqux'))
    $test_parse_foobarbazqux = nil
    assert_equal(nil, $&)
    assert_equal(nil, eval('alias $& $preserve_last_match'))
    assert_raise_with_message(SyntaxError, /as a global variable name\na = \$\#\n    \^~$/) do
      eval('a = $#')
    end
  end

  def test_invalid_instance_variable
    pattern = /without identifiers is not allowed as an instance variable name/
    assert_raise_with_message(SyntaxError, pattern) { eval('@%') }
    assert_raise_with_message(SyntaxError, pattern) { eval('@') }
  end

  def test_invalid_class_variable
    pattern = /without identifiers is not allowed as a class variable name/
    assert_raise_with_message(SyntaxError, pattern) { eval('@@%') }
    assert_raise_with_message(SyntaxError, pattern) { eval('@@') }
  end

  def test_invalid_char
    bug10117 = '[ruby-core:64243] [Bug #10117]'
    invalid_char = /Invalid char `\\x01'/
    x = 1
    assert_in_out_err(%W"-e \x01x", "", [], invalid_char, bug10117)
    assert_syntax_error("\x01x", invalid_char, bug10117)
    assert_equal(nil, eval("\x04x"))
    assert_equal 1, x
  end

  def test_literal_concat
    x = "baz"
    assert_equal("foobarbaz", eval('"foo" "bar#{x}"'))
    assert_equal("baz", x)
  end

  def test_unassignable
    assert_raise(SyntaxError) do
      eval %q(self = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(nil = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(true = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(false = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(__FILE__ = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(__LINE__ = 1)
    end
    assert_raise(SyntaxError) do
      eval %q(__ENCODING__ = 1)
    end
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def foo
          FOO = 1
        end
      END
    end
    assert_raise(SyntaxError) do
      eval "#{<<~"begin;"}\n#{<<~'end;'}", nil, __FILE__, __LINE__+1
      begin;
        x, true
      end;
    end
  end

  def test_block_dup
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        foo(&proc{}) {}
      END
    end
  end

  def test_set_backref
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        $& = 1
      END
    end
  end

  def test_arg_concat
    o = Object.new
    class << o; self; end.instance_eval do
      define_method(:[]=) {|*r, &b| b.call(r) }
    end
    r = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o[&proc{|x| r = x }] = 1
      END
    end
    assert_equal([1], r)
  end

  def test_void_expr_stmts_value
    # This test checks if void contexts are warned correctly.
    # Thus, warnings MUST NOT be suppressed.
    $VERBOSE = true
    stderr = $stderr
    $stderr = StringIO.new("")
    x = 1
    assert_nil eval("x; nil")
    assert_nil eval("1+1; nil")
    assert_nil eval("1.+(1); nil")
    assert_nil eval("TestParse; nil")
    assert_nil eval("::TestParse; nil")
    assert_nil eval("x..x; nil")
    assert_nil eval("x...x; nil")
    assert_nil eval("self; nil")
    assert_nil eval("nil; nil")
    assert_nil eval("true; nil")
    assert_nil eval("false; nil")
    assert_nil eval("defined?(1); nil")
    assert_equal 1, x

    assert_raise(SyntaxError) do
      eval %q(1; next; 2)
    end

    assert_equal(13, $stderr.string.lines.to_a.size)
    $stderr = stderr
  end

  def test_assign_in_conditional
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        (x, y = 1, 2) ? 1 : 2
      END
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        if @x = true
          1
        else
          2
        end
      END
    end
  end

  def test_literal_in_conditional
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        "foo" ? 1 : 2
      END
    end

    assert_nothing_raised do
      x = "bar"
      eval <<-END, nil, __FILE__, __LINE__+1
        /foo#{x}baz/ ? 1 : 2
      END
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        (true..false) ? 1 : 2
      END
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        ("foo".."bar") ? 1 : 2
      END
    end

    assert_nothing_raised do
      x = "bar"
      eval <<-END, nil, __FILE__, __LINE__+1
        :"foo#{"x"}baz" ? 1 : 2
      END
      assert_equal "bar", x
    end
  end

  def test_no_blockarg
    assert_raise(SyntaxError) do
      eval <<-END, nil, __FILE__, __LINE__+1
        yield(&:+)
      END
    end
  end

  def test_method_block_location
    bug5614 = '[ruby-core:40936]'
    expected = nil
    e = assert_raise(NoMethodError) do
      1.times do
        expected = __LINE__+1
      end.print do
        #
      end
    end
    actual = e.backtrace.first[/\A#{Regexp.quote(__FILE__)}:(\d+):/o, 1].to_i
    assert_equal(expected, actual, bug5614)
  end

  def test_no_shadowing_variable_warning
    assert_no_warning(/shadowing outer local variable/) {eval("a=1; tap {|a|}")}
  end

  def test_unused_variable
    o = Object.new
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo; a=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def bar; a=1; a(); end")}
    a = "\u{3042}"
    assert_warning(/#{a}/) {o.instance_eval("def foo0; #{a}=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo1; tap {a=1; a()}; end")}
    assert_warning('') {o.instance_eval("def bar1; a=a=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def bar2; a, = 1, 2; end")}
    assert_warning('') {o.instance_eval("def marg1(a); nil; end")}
    assert_warning('') {o.instance_eval("def marg2((a)); nil; end")}
  end

  def test_named_capture_conflict
    a = 1
    assert_warning('') {eval("a = 1; /(?<a>)/ =~ ''")}
    a = "\u{3042}"
    assert_warning('') {eval("#{a} = 1; /(?<#{a}>)/ =~ ''")}
  end

  def test_rescue_in_command_assignment
    bug = '[ruby-core:75621] [Bug #12402]'
    all_assertions(bug) do |a|
      a.for("lhs = arg") do
        v = bug
        v = raise(bug) rescue "ok"
        assert_equal("ok", v)
      end
      a.for("lhs op_asgn arg") do
        v = 0
        v += raise(bug) rescue 1
        assert_equal(1, v)
      end
      a.for("lhs[] op_asgn arg") do
        v = [0]
        v[0] += raise(bug) rescue 1
        assert_equal([1], v)
      end
      a.for("lhs.m op_asgn arg") do
        k = Struct.new(:m)
        v = k.new(0)
        v.m += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::m op_asgn arg") do
        k = Struct.new(:m)
        v = k.new(0)
        v::m += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs.C op_asgn arg") do
        k = Struct.new(:C)
        v = k.new(0)
        v.C += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::C op_asgn arg") do
        v = Class.new
        v::C ||= raise(bug) rescue 1
        assert_equal(1, v::C)
      end
      a.for("lhs = command") do
        v = bug
        v = raise bug rescue "ok"
        assert_equal("ok", v)
      end
      a.for("lhs op_asgn command") do
        v = 0
        v += raise bug rescue 1
        assert_equal(1, v)
      end
      a.for("lhs[] op_asgn command") do
        v = [0]
        v[0] += raise bug rescue 1
        assert_equal([1], v)
      end
      a.for("lhs.m op_asgn command") do
        k = Struct.new(:m)
        v = k.new(0)
        v.m += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::m op_asgn command") do
        k = Struct.new(:m)
        v = k.new(0)
        v::m += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs.C op_asgn command") do
        k = Struct.new(:C)
        v = k.new(0)
        v.C += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::C op_asgn command") do
        v = Class.new
        v::C ||= raise bug rescue 1
        assert_equal(1, v::C)
      end
    end
  end

  def test_yyerror_at_eol
    assert_syntax_error("    0b", /\^/)
    assert_syntax_error("    0b\n", /\^/)
  end

  def test_error_def_in_argument
    assert_separately([], "#{<<-"begin;"}\n#{<<~"end;"}")
    begin;
      assert_syntax_error("def f r:def d; def f 0end", /unexpected/)
    end;

    assert_syntax_error("def\nf(000)end", /^  \^~~/)
    assert_syntax_error("def\nf(&)end", /^   \^/)
  end

  def test_method_location_in_rescue
    bug = '[ruby-core:79388] [Bug #13181]'
    obj, line = Object.new, __LINE__+1
    def obj.location
      #
      raise
    rescue
      caller_locations(1, 1)[0]
    end

    assert_equal(line, obj.location.lineno, bug)
  end

  def test_negative_line_number
    bug = '[ruby-core:80920] [Bug #13523]'
    obj = Object.new
    obj.instance_eval("def t(e = false);raise if e; __LINE__;end", "test", -100)
    assert_equal(-100, obj.t, bug)
    assert_equal(-100, obj.method(:t).source_location[1], bug)
    e = assert_raise(RuntimeError) {obj.t(true)}
    assert_equal(-100, e.backtrace_locations.first.lineno, bug)
  end

  def test_file_in_indented_heredoc
    name = '[ruby-core:80987] [Bug #13540]' # long enough to be shared
    assert_equal(name+"\n", eval("#{<<-"begin;"}\n#{<<-'end;'}", nil, name))
    begin;
      <<~HEREDOC
        #{__FILE__}
      HEREDOC
    end;
  end

  def test_unexpected_token_error
    assert_raise(SyntaxError) do
      eval('"x"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
    end
  end

  def test_unexpected_token_after_numeric
    assert_raise_with_message(SyntaxError, /^    \^~~\Z/) do
      eval('0000xyz')
    end
    assert_raise_with_message(SyntaxError, /^    \^~~\Z/) do
      eval('1.2i1.1')
    end
    assert_raise_with_message(SyntaxError, /^   \^~\Z/) do
      eval('1.2.3')
    end
  end

  def test_truncated_source_line
    e = assert_raise_with_message(SyntaxError, /unexpected local variable or method/) do
      eval("'0123456789012345678901234567890123456789' abcdefghijklmnopqrstuvwxyz0123456789 0123456789012345678901234567890123456789")
    end
    line = e.message.lines[1]
    assert_operator(line, :start_with?, "...")
    assert_operator(line, :end_with?, "...\n")
  end

  def test_unterminated_regexp_error
    e = assert_raise(SyntaxError) do
      eval("/x")
    end.message
    assert_match(/unterminated regexp meets end of file/, e)
    assert_not_match(/unexpected tSTRING_END/, e)
  end

  def test_lparenarg
    o = Struct.new(:x).new
    def o.i(x)
      self.x = x
    end
    o.instance_eval {i (-1.3).abs}
    assert_equal(1.3, o.x)
    o.i(nil)
    o.instance_eval {i = 0; i (-1.3).abs; i}
    assert_equal(1.3, o.x)
  end

  def test_serial_comparison
    assert_warning(/comparison '<' after/) do
      $VERBOSE = true
      x = 1
      eval("if false; 0 < x < 2; end")
      x
    end
  end

  def test_eof_in_def
    assert_raise(SyntaxError) { eval("def m\n\0""end") }
    assert_raise(SyntaxError) { eval("def m\n\C-d""end") }
    assert_raise(SyntaxError) { eval("def m\n\C-z""end") }
  end

  def test_location_of_invalid_token
    assert_raise_with_message(SyntaxError, /^      \^~~\Z/) do
      eval('class xxx end')
    end
  end

  def test_whitespace_warning
    assert_raise_with_message(SyntaxError, /backslash/) do
      eval("\\foo")
    end
    assert_raise_with_message(SyntaxError, /escaped space/) do
      eval("\\ ")
    end
    assert_raise_with_message(SyntaxError, /escaped horizontal tab/) do
      eval("\\\t")
    end
    assert_raise_with_message(SyntaxError, /escaped form feed/) do
      eval("\\\f")
    end
    assert_raise_with_message(SyntaxError, /escaped carriage return/) do
      assert_warn(/middle of line/) {eval("\\\r")}
    end
    assert_raise_with_message(SyntaxError, /escaped vertical tab/) do
      eval("\\\v")
    end
  end

  def test_command_def_cmdarg
    assert_valid_syntax("\n#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      m def x(); end
      1.tap do end
    end;
  end

  NONASCII_CONSTANTS = [
    *%W"\u{00de} \u{00C0}".flat_map {|c| [c, c.encode("iso-8859-15")]},
    "\u{1c4}", "\u{1f2}", "\u{1f88}", "\u{370}",
    *%W"\u{391} \u{ff21}".flat_map {|c| [c, c.encode("cp932"), c.encode("euc-jp")]},
  ]

  def assert_nonascii_const
    assert_all_assertions_foreach("NONASCII_CONSTANTS", *NONASCII_CONSTANTS) do |n|
      m = Module.new
      assert_not_operator(m, :const_defined?, n)
      assert_raise_with_message(NameError, /uninitialized/) do
        m.const_get(n)
      end
      assert_nil(eval("defined?(m::#{n})"))

      v = yield m, n

      assert_operator(m, :const_defined?, n)
      assert_equal("constant", eval("defined?(m::#{n})"))
      assert_same(v, m.const_get(n))

      m.__send__(:remove_const, n)
      assert_not_operator(m, :const_defined?, n)
      assert_nil(eval("defined?(m::#{n})"))
    end
  end

  def test_nonascii_const_set
    assert_nonascii_const do |m, n|
      m.const_set(n, 42)
    end
  end

  def test_nonascii_constant
    assert_nonascii_const do |m, n|
      m.module_eval("class #{n}; self; end")
    end
  end

  def test_cdmarg_after_command_args_and_tlbrace_arg
    assert_valid_syntax('let () { m(a) do; end }')
  end

=begin
  def test_past_scope_variable
    assert_warning(/past scope/) {catch {|tag| eval("BEGIN{throw tag}; tap {a = 1}; a")}}
  end
=end
end
