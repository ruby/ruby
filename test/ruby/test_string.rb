# frozen_string_literal: false
require 'test/unit'

class TestString < Test::Unit::TestCase
  WIDE_ENCODINGS = [
     Encoding::UTF_16BE, Encoding::UTF_16LE,
     Encoding::UTF_32BE, Encoding::UTF_32LE,
  ]

  def initialize(*args)
    @cls = String
    @aref_re_nth = true
    @aref_re_silent = false
    @aref_slicebang_silent = true
    super
  end

  def S(*args, **kw)
    @cls.new(*args, **kw)
  end

  def test_s_new
    assert_equal("", S())
    assert_equal(Encoding::ASCII_8BIT, S().encoding)

    assert_equal("", S(""))
    assert_equal(__ENCODING__, S("").encoding)

    src = "RUBY"
    assert_equal(src, S(src))
    assert_equal(__ENCODING__, S(src).encoding)

    src.force_encoding("euc-jp")
    assert_equal(src, S(src))
    assert_equal(Encoding::EUC_JP, S(src).encoding)


    assert_equal("", S(encoding: "euc-jp"))
    assert_equal(Encoding::EUC_JP, S(encoding: "euc-jp").encoding)

    assert_equal("", S("", encoding: "euc-jp"))
    assert_equal(Encoding::EUC_JP, S("", encoding: "euc-jp").encoding)

    src = "RUBY"
    assert_equal(src, S(src, encoding: "euc-jp"))
    assert_equal(Encoding::EUC_JP, S(src, encoding: "euc-jp").encoding)

    src.force_encoding("euc-jp")
    assert_equal(src, S(src, encoding: "utf-8"))
    assert_equal(Encoding::UTF_8, S(src, encoding: "utf-8").encoding)

    assert_equal("", S(capacity: 1000))
    assert_equal(Encoding::ASCII_8BIT, S(capacity: 1000).encoding)

    assert_equal("", S(capacity: 1000, encoding: "euc-jp"))
    assert_equal(Encoding::EUC_JP, S(capacity: 1000, encoding: "euc-jp").encoding)

    assert_equal("", S("", capacity: 1000))
    assert_equal(__ENCODING__, S("", capacity: 1000).encoding)

    assert_equal("", S("", capacity: 1000, encoding: "euc-jp"))
    assert_equal(Encoding::EUC_JP, S("", capacity: 1000, encoding: "euc-jp").encoding)
  end

  def test_initialize
    str = S("").freeze
    assert_equal("", str.__send__(:initialize))
    assert_raise(FrozenError){ str.__send__(:initialize, 'abc') }
    assert_raise(FrozenError){ str.__send__(:initialize, capacity: 1000) }
    assert_raise(FrozenError){ str.__send__(:initialize, 'abc', capacity: 1000) }
    assert_raise(FrozenError){ str.__send__(:initialize, encoding: 'euc-jp') }
    assert_raise(FrozenError){ str.__send__(:initialize, 'abc', encoding: 'euc-jp') }
    assert_raise(FrozenError){ str.__send__(:initialize, 'abc', capacity: 1000, encoding: 'euc-jp') }

    str = S("")
    assert_equal("mystring", str.__send__(:initialize, "mystring"))
    str = S("mystring")
    assert_equal("mystring", str.__send__(:initialize, str))
    str = S("")
    assert_equal("mystring", str.__send__(:initialize, "mystring", capacity: 1000))
    str = S("mystring")
    assert_equal("mystring", str.__send__(:initialize, str, capacity: 1000))

    if @cls == String
      100.times {
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".
          __send__(:initialize, capacity: -1)
      }
    end
  end

  def test_initialize_shared
    S(str = "mystring" * 10).__send__(:initialize, capacity: str.bytesize)
    assert_equal("mystring", str[0, 8])
  end

  def test_initialize_nonstring
    assert_raise(TypeError) {
      S(1)
    }
    assert_raise(TypeError) {
      S(1, capacity: 1000)
    }
  end

  def test_initialize_memory_leak
    return unless @cls == String

    assert_no_memory_leak([], <<-PREP, <<-CODE, rss: true)
code = proc {('x'*100000).__send__(:initialize, '')}
1_000.times(&code)
PREP
100_000.times(&code)
CODE
  end

  # Bug #18154
  def test_initialize_nofree_memory_leak
    return unless @cls == String

    assert_no_memory_leak([], <<-PREP, <<-CODE, rss: true)
code = proc {0.to_s.__send__(:initialize, capacity: 10000)}
1_000.times(&code)
PREP
100_000.times(&code)
CODE
  end

  def test_AREF # '[]'
    assert_equal("A",  S("AooBar")[0])
    assert_equal("B",  S("FooBaB")[-1])
    assert_equal(nil, S("FooBar")[6])
    assert_equal(nil, S("FooBar")[-7])

    assert_equal(S("Foo"), S("FooBar")[0,3])
    assert_equal(S("Bar"), S("FooBar")[-3,3])
    assert_equal(S(""),    S("FooBar")[6,2])
    assert_equal(nil,      S("FooBar")[-7,10])

    assert_equal(S("Foo"), S("FooBar")[0..2])
    assert_equal(S("Foo"), S("FooBar")[0...3])
    assert_equal(S("Bar"), S("FooBar")[-3..-1])
    assert_equal(S(""),    S("FooBar")[6..2])
    assert_equal(nil,      S("FooBar")[-10..-7])

    assert_equal(S("Foo"), S("FooBar")[/^F../])
    assert_equal(S("Bar"), S("FooBar")[/..r$/])
    assert_equal(nil,      S("FooBar")[/xyzzy/])
    assert_equal(nil,      S("FooBar")[/plugh/])

    assert_equal(S("Foo"), S("FooBar")[S("Foo")])
    assert_equal(S("Bar"), S("FooBar")[S("Bar")])
    assert_equal(nil,      S("FooBar")[S("xyzzy")])
    assert_equal(nil,      S("FooBar")[S("plugh")])

    if @aref_re_nth
      assert_equal(S("Foo"), S("FooBar")[/([A-Z]..)([A-Z]..)/, 1])
      assert_equal(S("Bar"), S("FooBar")[/([A-Z]..)([A-Z]..)/, 2])
      assert_equal(nil,      S("FooBar")[/([A-Z]..)([A-Z]..)/, 3])
      assert_equal(S("Bar"), S("FooBar")[/([A-Z]..)([A-Z]..)/, -1])
      assert_equal(S("Foo"), S("FooBar")[/([A-Z]..)([A-Z]..)/, -2])
      assert_equal(nil,      S("FooBar")[/([A-Z]..)([A-Z]..)/, -3])
    end

    o = Object.new
    def o.to_int; 2; end
    assert_equal("o", "foo"[o])

    assert_raise(ArgumentError) { "foo"[] }
  end

  def test_ASET # '[]='
    s = S("FooBar")
    s[0] = S('A')
    assert_equal(S("AooBar"), s)

    s[-1]= S('B')
    assert_equal(S("AooBaB"), s)
    assert_raise(IndexError) { s[-7] = S("xyz") }
    assert_equal(S("AooBaB"), s)
    s[0] = S("ABC")
    assert_equal(S("ABCooBaB"), s)

    s = S("FooBar")
    s[0,3] = S("A")
    assert_equal(S("ABar"),s)
    s[0] = S("Foo")
    assert_equal(S("FooBar"), s)
    s[-3,3] = S("Foo")
    assert_equal(S("FooFoo"), s)
    assert_raise(IndexError) { s[7,3] =  S("Bar") }
    assert_raise(IndexError) { s[-7,3] = S("Bar") }

    s = S("FooBar")
    s[0..2] = S("A")
    assert_equal(S("ABar"), s)
    s[1..3] = S("Foo")
    assert_equal(S("AFoo"), s)
    s[-4..-4] = S("Foo")
    assert_equal(S("FooFoo"), s)
    assert_raise(RangeError) { s[7..10]   = S("Bar") }
    assert_raise(RangeError) { s[-7..-10] = S("Bar") }

    s = S("FooBar")
    s[/^F../]= S("Bar")
    assert_equal(S("BarBar"), s)
    s[/..r$/] = S("Foo")
    assert_equal(S("BarFoo"), s)
    if @aref_re_silent
      s[/xyzzy/] = S("None")
      assert_equal(S("BarFoo"), s)
    else
      assert_raise(IndexError) { s[/xyzzy/] = S("None") }
    end
    if @aref_re_nth
      s[/([A-Z]..)([A-Z]..)/, 1] = S("Foo")
      assert_equal(S("FooFoo"), s)
      s[/([A-Z]..)([A-Z]..)/, 2] = S("Bar")
      assert_equal(S("FooBar"), s)
      assert_raise(IndexError) { s[/([A-Z]..)([A-Z]..)/, 3] = "None" }
      s[/([A-Z]..)([A-Z]..)/, -1] = S("Foo")
      assert_equal(S("FooFoo"), s)
      s[/([A-Z]..)([A-Z]..)/, -2] = S("Bar")
      assert_equal(S("BarFoo"), s)
      assert_raise(IndexError) { s[/([A-Z]..)([A-Z]..)/, -3] = "None" }
    end

    s = S("FooBar")
    s[S("Foo")] = S("Bar")
    assert_equal(S("BarBar"), s)

    s = S("a string")
    s[0..s.size] = S("another string")
    assert_equal(S("another string"), s)

    o = Object.new
    def o.to_int; 2; end
    s = "foo"
    s[o] = "bar"
    assert_equal("fobar", s)

    assert_raise(ArgumentError) { "foo"[1, 2, 3] = "" }

    assert_raise(IndexError) {"foo"[RbConfig::LIMITS["LONG_MIN"]] = "l"}
  end

  def test_CMP # '<=>'
    assert_equal(1, S("abcdef") <=> S("abcde"))
    assert_equal(0, S("abcdef") <=> S("abcdef"))
    assert_equal(-1, S("abcde") <=> S("abcdef"))

    assert_equal(-1, S("ABCDEF") <=> S("abcdef"))

    assert_nil(S("foo") <=> Object.new)

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal(1, S("foo") <=> o)

    class << o;remove_method :to_str;end
    def o.<=>(x); nil; end
    assert_nil(S("foo") <=> o)

    class << o;remove_method :<=>;end
    def o.<=>(x); 1; end
    assert_equal(-1, S("foo") <=> o)

    class << o;remove_method :<=>;end
    def o.<=>(x); 2**100; end
    assert_equal(-1, S("foo") <=> o)
  end

  def test_EQUAL # '=='
    assert_not_equal(:foo, S("foo"))
    assert_equal(S("abcdef"), S("abcdef"))

    assert_not_equal(S("CAT"), S('cat'))
    assert_not_equal(S("CaT"), S('cAt'))
    assert_not_equal(S("cat\0""dog"), S("cat\0"))

    o = Object.new
    def o.to_str; end
    def o.==(x); false; end
    assert_equal(false, S("foo") == o)
    class << o;remove_method :==;end
    def o.==(x); true; end
    assert_equal(true, S("foo") == o)
  end

  def test_LSHIFT # '<<'
    assert_equal(S("world!"), S("world") << 33)
    assert_equal(S("world!"), S("world") << S("!"))

    s = "a"
    10.times {|i|
      s << s
      assert_equal("a" * (2 << i), s)
    }

    s = ["foo"].pack("p")
    l = s.size
    s << "bar"
    assert_equal(l + 3, s.size)

    bug = '[ruby-core:27583]'
    assert_raise(RangeError, bug) {S("a".force_encoding(Encoding::UTF_8)) << -3}
    assert_raise(RangeError, bug) {S("a".force_encoding(Encoding::UTF_8)) << -2}
    assert_raise(RangeError, bug) {S("a".force_encoding(Encoding::UTF_8)) << -1}
    assert_raise(RangeError, bug) {S("a".force_encoding(Encoding::UTF_8)) << 0x81308130}
    assert_nothing_raised {S("a".force_encoding(Encoding::GB18030)) << 0x81308130}

    s = "\x95".force_encoding(Encoding::SJIS).tap(&:valid_encoding?)
    assert_predicate(s << 0x5c, :valid_encoding?)
  end

  def test_MATCH # '=~'
    assert_equal(10,  S("FeeFieFoo-Fum") =~ /Fum$/)
    assert_equal(nil, S("FeeFieFoo-Fum") =~ /FUM$/)

    o = Object.new
    def o.=~(x); x + "bar"; end
    assert_equal("foobar", S("foo") =~ o)

    assert_raise(TypeError) { S("foo") =~ "foo" }
  end

  def test_MOD # '%'
    assert_equal(S("00123"), S("%05d") % 123)
    assert_equal(S("123  |00000001"), S("%-5s|%08x") % [123, 1])
    x = S("%3s %-4s%%foo %.0s%5d %#x%c%3.1f %b %x %X %#b %#x %#X") %
    [S("hi"),
      123,
      S("never seen"),
      456,
      0,
      ?A,
      3.0999,
      11,
      171,
      171,
      11,
      171,
      171]

    assert_equal(S(' hi 123 %foo   456 0A3.1 1011 ab AB 0b1011 0xab 0XAB'), x)
  end

  def test_MUL # '*'
    assert_equal(S("XXX"),  S("X") * 3)
    assert_equal(S("HOHO"), S("HO") * 2)
  end

  def test_PLUS # '+'
    assert_equal(S("Yodel"), S("Yo") + S("del"))
  end

  def casetest(a, b, rev=false)
    msg = proc {"#{a} should#{' not' if rev} match #{b}"}
    case a
    when b
      assert(!rev, msg)
    else
      assert(rev, msg)
    end
  end

  def test_VERY_EQUAL # '==='
    # assert_equal(true, S("foo") === :foo)
    casetest(S("abcdef"), S("abcdef"))

    casetest(S("CAT"), S('cat'), true) # Reverse the test - we don't want to
    casetest(S("CaT"), S('cAt'), true) # find these in the case.
  end

  def test_capitalize
    assert_equal(S("Hello"),  S("hello").capitalize)
    assert_equal(S("Hello"),  S("hELLO").capitalize)
    assert_equal(S("123abc"), S("123ABC").capitalize)
  end

  def test_capitalize!
    a = S("hello"); a.capitalize!
    assert_equal(S("Hello"), a)

    a = S("hELLO"); a.capitalize!
    assert_equal(S("Hello"), a)

    a = S("123ABC"); a.capitalize!
    assert_equal(S("123abc"), a)

    assert_equal(nil,         S("123abc").capitalize!)
    assert_equal(S("123abc"), S("123ABC").capitalize!)
    assert_equal(S("Abc"),    S("ABC").capitalize!)
    assert_equal(S("Abc"),    S("abc").capitalize!)
    assert_equal(nil,         S("Abc").capitalize!)

    a = S("hello")
    b = a.dup
    assert_equal(S("Hello"), a.capitalize!)
    assert_equal(S("hello"), b)

  end

  Bug2463 = '[ruby-dev:39856]'
  def test_center
    assert_equal(S("hello"),       S("hello").center(4))
    assert_equal(S("   hello   "), S("hello").center(11))
    assert_equal(S("ababaababa"), S("").center(10, "ab"), Bug2463)
    assert_equal(S("ababaababab"), S("").center(11, "ab"), Bug2463)
  end

  def test_chomp
    verbose, $VERBOSE = $VERBOSE, nil

    assert_equal(S("hello"), S("hello").chomp("\n"))
    assert_equal(S("hello"), S("hello\n").chomp("\n"))
    save = $/

    $/ = "\n"

    assert_equal(S("hello"), S("hello").chomp)
    assert_equal(S("hello"), S("hello\n").chomp)

    $/ = "!"
    assert_equal(S("hello"), S("hello").chomp)
    assert_equal(S("hello"), S("hello!").chomp)
    $/ = save

    assert_equal(S("a").hash, S("a\u0101").chomp(S("\u0101")).hash, '[ruby-core:22414]')

    s = S("hello")
    assert_equal("hel", s.chomp('lo'))
    assert_equal("hello", s)

    s = S("hello")
    assert_equal("hello", s.chomp('he'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b}", s.chomp("\u{3061 306f}"))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b 3061 306f}", s.chomp('lo'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal("hello", s.chomp("\u{3061 306f}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal("\xe3\x81\x82", s.chomp("\x82"))
    assert_equal("\xe3\x81\x82", s)

    s = S("\x95\x5c").force_encoding("Shift_JIS")
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s.chomp("\x5c"))
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s)

    # clear coderange
    s = S("hello\u{3053 3093}")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.chomp("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("abb", s.chomp(klass.new))
    assert_equal("abba", s)

    # chomp removes any of "\n", "\r\n", "\r" when "\n" is specified
    s = "foo\n"
    assert_equal("foo", s.chomp("\n"))
    s = "foo\r\n"
    assert_equal("foo", s.chomp("\n"))
    s = "foo\r"
    assert_equal("foo", s.chomp("\n"))
  ensure
    $/ = save
    $VERBOSE = verbose
  end

  def test_chomp!
    verbose, $VERBOSE = $VERBOSE, nil

    a = S("hello")
    a.chomp!(S("\n"))

    assert_equal(S("hello"), a)
    assert_equal(nil, a.chomp!(S("\n")))

    a = S("hello\n")
    a.chomp!(S("\n"))
    assert_equal(S("hello"), a)
    save = $/

    $/ = "\n"
    a = S("hello")
    a.chomp!
    assert_equal(S("hello"), a)

    a = S("hello\n")
    a.chomp!
    assert_equal(S("hello"), a)

    $/ = "!"
    a = S("hello")
    a.chomp!
    assert_equal(S("hello"), a)

    a="hello!"
    a.chomp!
    assert_equal(S("hello"), a)

    $/ = save

    a = S("hello\n")
    b = a.dup
    assert_equal(S("hello"), a.chomp!)
    assert_equal(S("hello\n"), b)

    s = "foo\r\n"
    s.chomp!
    assert_equal("foo", s)

    s = "foo\r"
    s.chomp!
    assert_equal("foo", s)

    s = "foo\r\n"
    s.chomp!("")
    assert_equal("foo", s)

    s = "foo\r"
    s.chomp!("")
    assert_equal("foo\r", s)

    assert_equal(S("a").hash, S("a\u0101").chomp!(S("\u0101")).hash, '[ruby-core:22414]')

    s = S("").freeze
    assert_raise_with_message(FrozenError, /frozen/) {s.chomp!}
    $VERBOSE = nil # EnvUtil.suppress_warning resets $VERBOSE to the original state

    s = S("ax")
    o = Struct.new(:s).new(s)
    def o.to_str
      s.freeze
      "x"
    end
    assert_raise_with_message(FrozenError, /frozen/) {s.chomp!(o)}
    $VERBOSE = nil # EnvUtil.suppress_warning resets $VERBOSE to the original state

    s = S("hello")
    assert_equal("hel", s.chomp!('lo'))
    assert_equal("hel", s)

    s = S("hello")
    assert_equal(nil, s.chomp!('he'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b}", s.chomp!("\u{3061 306f}"))
    assert_equal("\u{3053 3093 306b}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal(nil, s.chomp!('lo'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal(nil, s.chomp!("\u{3061 306f}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal(nil, s.chomp!("\x82"))
    assert_equal("\xe3\x81\x82", s)

    s = S("\x95\x5c").force_encoding("Shift_JIS")
    assert_equal(nil, s.chomp!("\x5c"))
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s)

    # clear coderange
    s = S("hello\u{3053 3093}")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.chomp!("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("abb", s.chomp!(klass.new))
    assert_equal("abb", s)

    # chomp removes any of "\n", "\r\n", "\r" when "\n" is specified
    s = "foo\n"
    assert_equal("foo", s.chomp!("\n"))
    s = "foo\r\n"
    assert_equal("foo", s.chomp!("\n"))
    s = "foo\r"
    assert_equal("foo", s.chomp!("\n"))
  ensure
    $/ = save
    $VERBOSE = verbose
  end

  def test_chop
    assert_equal(S("hell"),    S("hello").chop)
    assert_equal(S("hello"),   S("hello\r\n").chop)
    assert_equal(S("hello\n"), S("hello\n\r").chop)
    assert_equal(S(""),        S("\r\n").chop)
    assert_equal(S(""),        S("").chop)
    assert_equal(S("a").hash,  S("a\u00d8").chop.hash)
  end

  def test_chop!
    a = S("hello").chop!
    assert_equal(S("hell"), a)

    a = S("hello\r\n").chop!
    assert_equal(S("hello"), a)

    a = S("hello\n\r").chop!
    assert_equal(S("hello\n"), a)

    a = S("\r\n").chop!
    assert_equal(S(""), a)

    a = S("").chop!
    assert_nil(a)

    a = S("a\u00d8")
    a.chop!
    assert_equal(S("a").hash, a.hash)

    a = S("hello\n")
    b = a.dup
    assert_equal(S("hello"),   a.chop!)
    assert_equal(S("hello\n"), b)
  end

  def test_clone
    for frozen in [ false, true ]
      a = S("Cool")
      a.freeze if frozen
      b = a.clone

      assert_equal(a, b)
      assert_not_same(a, b)
      assert_equal(a.frozen?, b.frozen?)
    end

    assert_equal("", File.read(IO::NULL).clone, '[ruby-dev:32819] reported by Kazuhiro NISHIYAMA')
  end

  def test_concat
    assert_equal(S("world!"), S("world").concat(33))
    assert_equal(S("world!"), S("world").concat(S('!')))
    b = S("sn")
    assert_equal(S("snsnsn"), b.concat(b, b))

    bug7090 = '[ruby-core:47751]'
    result = S("").force_encoding(Encoding::UTF_16LE)
    result << 0x0300
    expected = S("\u0300".encode(Encoding::UTF_16LE))
    assert_equal(expected, result, bug7090)
    assert_raise(TypeError) { S('foo') << :foo }
    assert_raise(FrozenError) { S('foo').freeze.concat('bar') }
  end

  def test_concat_literals
    s=S("." * 50)
    assert_equal(Encoding::UTF_8, "#{s}x".encoding)
  end

  def test_count
    a = S("hello world")
    assert_equal(5, a.count(S("lo")))
    assert_equal(2, a.count(S("lo"), S("o")))
    assert_equal(4, a.count(S("hello"), S("^l")))
    assert_equal(4, a.count(S("ej-m")))
    assert_equal(0, S("y").count(S("a\\-z")))
    assert_equal(5, S("abc\u{3042 3044 3046}").count("^a"))
    assert_equal(1, S("abc\u{3042 3044 3046}").count("\u3042"))
    assert_equal(5, S("abc\u{3042 3044 3046}").count("^\u3042"))
    assert_equal(2, S("abc\u{3042 3044 3046}").count("a-z", "^a"))
    assert_equal(0, S("abc\u{3042 3044 3046}").count("a", "\u3042"))
    assert_equal(0, S("abc\u{3042 3044 3046}").count("\u3042", "a"))
    assert_equal(0, S("abc\u{3042 3044 3046}").count("\u3042", "\u3044"))
    assert_equal(4, S("abc\u{3042 3044 3046}").count("^a", "^\u3044"))
    assert_equal(4, S("abc\u{3042 3044 3046}").count("^\u3044", "^a"))
    assert_equal(4, S("abc\u{3042 3044 3046}").count("^\u3042", "^\u3044"))

    assert_raise(ArgumentError) { S("foo").count }
  end

  def crypt_supports_des_crypt?
    /openbsd/ !~ RUBY_PLATFORM
  end

  def test_crypt
    if crypt_supports_des_crypt?
      pass      = "aaGUC/JkO9/Sc"
      good_salt = "aa"
      bad_salt  = "ab"
    else
      pass      = "$2a$04$0WVaz0pV3jzfZ5G5tpmHWuBQGbkjzgtSc3gJbmdy0GAGMa45MFM2."
      good_salt = "$2a$04$0WVaz0pV3jzfZ5G5tpmHWu"
      bad_salt  = "$2a$04$0WVaz0pV3jzfZ5G5tpmHXu"
    end
    assert_equal(S(pass), S("mypassword").crypt(S(good_salt)))
    assert_not_equal(S(pass), S("mypassword").crypt(S(bad_salt)))
    assert_raise(ArgumentError) {S("mypassword").crypt(S(""))}
    assert_raise(ArgumentError) {S("mypassword").crypt(S("\0a"))}
    assert_raise(ArgumentError) {S("mypassword").crypt(S("a\0"))}
    assert_raise(ArgumentError) {S("poison\u0000null").crypt(S("aa"))}
    WIDE_ENCODINGS.each do |enc|
      assert_raise(ArgumentError) {S("mypassword").crypt(S("aa".encode(enc)))}
      assert_raise(ArgumentError) {S("mypassword".encode(enc)).crypt(S("aa"))}
    end

    @cls == String and
      assert_no_memory_leak([], "s = ''; salt_proc = proc{#{(crypt_supports_des_crypt? ? '..' : good_salt).inspect}}", "#{<<~"begin;"}\n#{<<~'end;'}")

    begin;
      1000.times { s.crypt(-salt_proc.call).clear  }
    end;
  end

  def test_delete
    assert_equal(S("heo"),  S("hello").delete(S("l"), S("lo")))
    assert_equal(S("he"),   S("hello").delete(S("lo")))
    assert_equal(S("hell"), S("hello").delete(S("aeiou"), S("^e")))
    assert_equal(S("ho"),   S("hello").delete(S("ej-m")))

    assert_equal(S("a").hash, S("a\u0101").delete("\u0101").hash, '[ruby-talk:329267]')
    assert_equal(true, S("a\u0101").delete("\u0101").ascii_only?)
    assert_equal(true, S("a\u3041").delete("\u3041").ascii_only?)
    assert_equal(false, S("a\u3041\u3042").delete("\u3041").ascii_only?)

    assert_equal("a", S("abc\u{3042 3044 3046}").delete("^a"))
    assert_equal("bc\u{3042 3044 3046}", S("abc\u{3042 3044 3046}").delete("a"))
    assert_equal("\u3042", S("abc\u{3042 3044 3046}").delete("^\u3042"))

    bug6160 = '[ruby-dev:45374]'
    assert_equal("", S('\\').delete('\\'), bug6160)
  end

  def test_delete!
    a = S("hello")
    a.delete!(S("l"), S("lo"))
    assert_equal(S("heo"), a)

    a = S("hello")
    a.delete!(S("lo"))
    assert_equal(S("he"), a)

    a = S("hello")
    a.delete!(S("aeiou"), S("^e"))
    assert_equal(S("hell"), a)

    a = S("hello")
    a.delete!(S("ej-m"))
    assert_equal(S("ho"), a)

    a = S("hello")
    assert_nil(a.delete!(S("z")))

    a = S("hello")
    b = a.dup
    a.delete!(S("lo"))
    assert_equal(S("he"), a)
    assert_equal(S("hello"), b)

    a = S("hello")
    a.delete!(S("^el"))
    assert_equal(S("ell"), a)

    assert_raise(ArgumentError) { S("foo").delete! }
  end


  def test_downcase
    assert_equal(S("hello"), S("helLO").downcase)
    assert_equal(S("hello"), S("hello").downcase)
    assert_equal(S("hello"), S("HELLO").downcase)
    assert_equal(S("abc hello 123"), S("abc HELLO 123").downcase)
    assert_equal(S("h\0""ello"), S("h\0""ELLO").downcase)
  end

  def test_downcase!
    a = S("helLO")
    b = a.dup
    assert_equal(S("hello"), a.downcase!)
    assert_equal(S("hello"), a)
    assert_equal(S("helLO"), b)

    a=S("hello")
    assert_nil(a.downcase!)
    assert_equal(S("hello"), a)

    a = S("h\0""ELLO")
    b = a.dup
    assert_equal(S("h\0""ello"), a.downcase!)
    assert_equal(S("h\0""ello"), a)
    assert_equal(S("h\0""ELLO"), b)
  end

  def test_dump
    a= S("Test") << 1 << 2 << 3 << 9 << 13 << 10
    assert_equal(S('"Test\\x01\\x02\\x03\\t\\r\\n"'), a.dump)
    b= S("\u{7F}")
    assert_equal(S('"\\x7F"'), b.dump)
    b= S("\u{AB}")
    assert_equal(S('"\\u00AB"'), b.dump)
    b= S("\u{ABC}")
    assert_equal(S('"\\u0ABC"'), b.dump)
    b= S("\uABCD")
    assert_equal(S('"\\uABCD"'), b.dump)
    b= S("\u{ABCDE}")
    assert_equal(S('"\\u{ABCDE}"'), b.dump)
    b= S("\u{10ABCD}")
    assert_equal(S('"\\u{10ABCD}"'), b.dump)
  end

  def test_undump
    a = S("Test") << 1 << 2 << 3 << 9 << 13 << 10
    assert_equal(a, S('"Test\\x01\\x02\\x03\\t\\r\\n"').undump)
    assert_equal(S("\\ca"), S('"\\ca"').undump)
    assert_equal(S("\u{7F}"), S('"\\x7F"').undump)
    assert_equal(S("\u{7F}A"), S('"\\x7FA"').undump)
    assert_equal(S("\u{AB}"), S('"\\u00AB"').undump)
    assert_equal(S("\u{ABC}"), S('"\\u0ABC"').undump)
    assert_equal(S("\uABCD"), S('"\\uABCD"').undump)
    assert_equal(S("\uABCD"), S('"\\uABCD"').undump)
    assert_equal(S("\u{ABCDE}"), S('"\\u{ABCDE}"').undump)
    assert_equal(S("\u{10ABCD}"), S('"\\u{10ABCD}"').undump)
    assert_equal(S("\u{ABCDE 10ABCD}"), S('"\\u{ABCDE 10ABCD}"').undump)
    assert_equal(S(""), S('"\\u{}"').undump)
    assert_equal(S(""), S('"\\u{  }"').undump)

    assert_equal(S("\u3042".encode("sjis")), S('"\x82\xA0"'.force_encoding("sjis")).undump)
    assert_equal(S("\u8868".encode("sjis")), S("\"\\x95\\\\\"".force_encoding("sjis")).undump)

    assert_equal(S("äöü"), S('"\u00E4\u00F6\u00FC"').undump)
    assert_equal(S("äöü"), S('"\xC3\xA4\xC3\xB6\xC3\xBC"').undump)

    assert_equal(Encoding::UTF_8, S('"\\u3042"').encode(Encoding::EUC_JP).undump.encoding)

    assert_equal("abc".encode(Encoding::UTF_16LE),
                 S('"a\x00b\x00c\x00".force_encoding("UTF-16LE")').undump)

    assert_equal('\#', S('"\\\\#"').undump)
    assert_equal('\#{', S('"\\\\\#{"').undump)

    assert_raise(RuntimeError) { S('\u3042').undump }
    assert_raise(RuntimeError) { S('"\x82\xA0\u3042"'.force_encoding("SJIS")).undump }
    assert_raise(RuntimeError) { S('"\u3042\x82\xA0"'.force_encoding("SJIS")).undump }
    assert_raise(RuntimeError) { S('"".force_encoding()').undump }
    assert_raise(RuntimeError) { S('"".force_encoding("').undump }
    assert_raise(RuntimeError) { S('"".force_encoding("UNKNOWN")').undump }
    assert_raise(RuntimeError) { S('"\u3042".force_encoding("UTF-16LE")').undump }
    assert_raise(RuntimeError) { S('"\x00\x00".force_encoding("UTF-16LE")"').undump }
    assert_raise(RuntimeError) { S('"\x00\x00".force_encoding("'+("a"*9999999)+'")"').undump }
    assert_raise(RuntimeError) { S(%("\u00E4")).undump }
    assert_raise(RuntimeError) { S('"').undump }
    assert_raise(RuntimeError) { S('"""').undump }
    assert_raise(RuntimeError) { S('""""').undump }

    assert_raise(RuntimeError) { S('"a').undump }
    assert_raise(RuntimeError) { S('"\u"').undump }
    assert_raise(RuntimeError) { S('"\u{"').undump }
    assert_raise(RuntimeError) { S('"\u304"').undump }
    assert_raise(RuntimeError) { S('"\u304Z"').undump }
    assert_raise(RuntimeError) { S('"\udfff"').undump }
    assert_raise(RuntimeError) { S('"\u{dfff}"').undump }
    assert_raise(RuntimeError) { S('"\u{3042"').undump }
    assert_raise(RuntimeError) { S('"\u{3042 "').undump }
    assert_raise(RuntimeError) { S('"\u{110000}"').undump }
    assert_raise(RuntimeError) { S('"\u{1234567}"').undump }
    assert_raise(RuntimeError) { S('"\x"').undump }
    assert_raise(RuntimeError) { S('"\xA"').undump }
    assert_raise(RuntimeError) { S('"\\"').undump }
    assert_raise(RuntimeError) { S(%("\0")).undump }
    assert_raise_with_message(RuntimeError, /invalid/) {
      S('"\\u{007F}".xxxxxx').undump
    }
  end

  def test_dup
    for frozen in [ false, true ]
      a = S("hello")
      a.freeze if frozen
      b = a.dup

      assert_equal(a, b)
      assert_not_same(a, b)
      assert_not_predicate(b, :frozen?)
    end
  end

  class StringWithIVSet < String
    def set_iv
      @foo = 1
    end
  end

  def test_ivar_set_after_frozen_dup
    str = StringWithIVSet.new.freeze
    str.dup.set_iv
    assert_raise(FrozenError) { str.set_iv }
  end

  def test_each
    verbose, $VERBOSE = $VERBOSE, nil

    save = $/
    $/ = "\n"
    res=[]
    S("hello\nworld").lines.each {|x| res << x}
    assert_equal(S("hello\n"), res[0])
    assert_equal(S("world"),   res[1])

    res=[]
    S("hello\n\n\nworld").lines(S('')).each {|x| res << x}
    assert_equal(S("hello\n\n"), res[0])
    assert_equal(S("world"),     res[1])

    $/ = "!"
    res=[]
    S("hello!world").lines.each {|x| res << x}
    assert_equal(S("hello!"), res[0])
    assert_equal(S("world"),  res[1])
  ensure
    $/ = save
    $VERBOSE = verbose
  end

  def test_each_byte
    s = S("ABC")

    res = []
    assert_equal s.object_id, s.each_byte {|x| res << x }.object_id
    assert_equal(65, res[0])
    assert_equal(66, res[1])
    assert_equal(67, res[2])

    assert_equal 65, s.each_byte.next
  end

  def test_bytes
    s = S("ABC")
    assert_equal [65, 66, 67], s.bytes

    res = []
    assert_equal s.object_id, s.bytes {|x| res << x }.object_id
    assert_equal(65, res[0])
    assert_equal(66, res[1])
    assert_equal(67, res[2])
    s = S("ABC")
    res = []
    assert_same s, s.bytes {|x| res << x }
    assert_equal [65, 66, 67], res
  end

  def test_each_codepoint
    # Single byte optimization
    assert_equal 65, S("ABC").each_codepoint.next

    s = S("\u3042\u3044\u3046")

    res = []
    assert_equal s.object_id, s.each_codepoint {|x| res << x }.object_id
    assert_equal(0x3042, res[0])
    assert_equal(0x3044, res[1])
    assert_equal(0x3046, res[2])

    assert_equal 0x3042, s.each_codepoint.next
  end

  def test_codepoints
    # Single byte optimization
    assert_equal [65, 66, 67], S("ABC").codepoints

    s = S("\u3042\u3044\u3046")
    assert_equal [0x3042, 0x3044, 0x3046], s.codepoints

    res = []
    assert_equal s.object_id, s.codepoints {|x| res << x }.object_id
    assert_equal(0x3042, res[0])
    assert_equal(0x3044, res[1])
    assert_equal(0x3046, res[2])
    s = S("ABC")
    res = []
    assert_same s, s.codepoints {|x| res << x }
    assert_equal [65, 66, 67], res
  end

  def test_each_char
    s = S("ABC")

    res = []
    assert_equal s.object_id, s.each_char {|x| res << x }.object_id
    assert_equal("A", res[0])
    assert_equal("B", res[1])
    assert_equal("C", res[2])

    assert_equal "A", S("ABC").each_char.next
  end

  def test_chars
    s = S("ABC")
    assert_equal ["A", "B", "C"], s.chars

    res = []
    assert_equal s.object_id, s.chars {|x| res << x }.object_id
    assert_equal("A", res[0])
    assert_equal("B", res[1])
    assert_equal("C", res[2])
  end

  def test_each_grapheme_cluster
    [
      "\u{0D 0A}",
      "\u{20 200d}",
      "\u{600 600}",
      "\u{600 20}",
      "\u{261d 1F3FB}",
      "\u{1f600}",
      "\u{20 308}",
      "\u{1F477 1F3FF 200D 2640 FE0F}",
      "\u{1F468 200D 1F393}",
      "\u{1F46F 200D 2642 FE0F}",
      "\u{1f469 200d 2764 fe0f 200d 1f469}",
    ].each do |g|
      assert_equal [g], g.each_grapheme_cluster.to_a
      assert_equal 1, g.each_grapheme_cluster.size
    end

    [
      ["\u{a 324}", ["\u000A", "\u0324"]],
      ["\u{d 324}", ["\u000D", "\u0324"]],
      ["abc", ["a", "b", "c"]],
    ].each do |str, grapheme_clusters|
      assert_equal grapheme_clusters, str.each_grapheme_cluster.to_a
      assert_equal grapheme_clusters.size, str.each_grapheme_cluster.size
    end

    s = ("x"+"\u{10ABCD}"*250000)
    assert_empty(s.each_grapheme_cluster {s.clear})
  end

  def test_grapheme_clusters
    [
      "\u{20 200d}",
      "\u{600 600}",
      "\u{600 20}",
      "\u{261d 1F3FB}",
      "\u{1f600}",
      "\u{20 308}",
      "\u{1F477 1F3FF 200D 2640 FE0F}",
      "\u{1F468 200D 1F393}",
      "\u{1F46F 200D 2642 FE0F}",
      "\u{1f469 200d 2764 fe0f 200d 1f469}",
    ].product([Encoding::UTF_8, *WIDE_ENCODINGS]) do |g, enc|
      g = g.encode(enc)
      assert_equal [g], g.grapheme_clusters
    end

    [
      "\u{a 324}",
      "\u{d 324}",
      "abc",
    ].product([Encoding::UTF_8, *WIDE_ENCODINGS]) do |g, enc|
      g = g.encode(enc)
      assert_equal g.chars, g.grapheme_clusters
    end
    assert_equal ["a", "b", "c"], S("abc").b.grapheme_clusters

    s = S("ABC").b
    res = []
    assert_same s, s.grapheme_clusters {|x| res << x }
    assert_equal(3, res.size)
    assert_equal("A", res[0])
    assert_equal("B", res[1])
    assert_equal("C", res[2])
  end

  def test_grapheme_clusters_memory_leak
    assert_no_memory_leak([], "", "#{<<~"begin;"}\n#{<<~'end;'}", "[Bug #todo]", rss: true)
    begin;
      str = "hello world".encode(Encoding::UTF_32LE)

      10_000.times do
        str.grapheme_clusters
      end
    end;
  end

  def test_each_line
    verbose, $VERBOSE = $VERBOSE, nil

    save = $/
    $/ = "\n"
    res=[]
    S("hello\nworld").each_line {|x| res << x}
    assert_equal(S("hello\n"), res[0])
    assert_equal(S("world"),   res[1])

    res=[]
    S("hello\n\n\nworld").each_line(S('')) {|x| res << x}
    assert_equal(S("hello\n\n"), res[0])
    assert_equal(S("world"),     res[1])

    res=[]
    S("hello\r\n\r\nworld").each_line(S('')) {|x| res << x}
    assert_equal(S("hello\r\n\r\n"), res[0])
    assert_equal(S("world"),         res[1])

    $/ = "!"

    res=[]
    S("hello!world").each_line {|x| res << x}
    assert_equal(S("hello!"), res[0])
    assert_equal(S("world"),  res[1])

    $/ = "ab"

    res=[]
    S("a").lines.each {|x| res << x}
    assert_equal(1, res.size)
    assert_equal(S("a"), res[0])

    $/ = save

    s = nil
    S("foo\nbar").each_line(nil) {|s2| s = s2 }
    assert_equal("foo\nbar", s)

    assert_equal "hello\n", S("hello\nworld").each_line.next
    assert_equal "hello\nworld", S("hello\nworld").each_line(nil).next

    bug7646 = "[ruby-dev:46827]"
    assert_nothing_raised(bug7646) do
      S("\n\u0100").each_line("\n") {}
    end
  ensure
    $/ = save
    $VERBOSE = verbose
  end

  def test_each_line_chomp
    res = []
    S("hello\nworld").each_line("\n", chomp: true) {|x| res << x}
    assert_equal(S("hello"), res[0])
    assert_equal(S("world"), res[1])

    res = []
    S("hello\n\n\nworld\n").each_line(S(''), chomp: true) {|x| res << x}
    assert_equal(S("hello"), res[0])
    assert_equal(S("world\n"), res[1])

    res = []
    S("hello\r\n\r\nworld\r\n").each_line(S(''), chomp: true) {|x| res << x}
    assert_equal(S("hello"), res[0])
    assert_equal(S("world\r\n"), res[1])

    res = []
    S("hello\r\n\n\nworld").each_line(S(''), chomp: true) {|x| res << x}
    assert_equal(S("hello"), res[0])
    assert_equal(S("world"), res[1])

    res = []
    S("hello!world").each_line(S('!'), chomp: true) {|x| res << x}
    assert_equal(S("hello"), res[0])
    assert_equal(S("world"), res[1])

    res = []
    S("a").each_line(S('ab'), chomp: true).each {|x| res << x}
    assert_equal(1, res.size)
    assert_equal(S("a"), res[0])

    s = nil
    S("foo\nbar").each_line(nil, chomp: true) {|s2| s = s2 }
    assert_equal("foo\nbar", s)

    assert_equal "hello", S("hello\nworld").each_line(chomp: true).next
    assert_equal "hello\nworld", S("hello\nworld").each_line(nil, chomp: true).next

    res = []
    S("").each_line(chomp: true) {|x| res << x}
    assert_equal([], res)

    res = []
    S("\n").each_line(chomp: true) {|x| res << x}
    assert_equal([S("")], res)

    res = []
    S("\r\n").each_line(chomp: true) {|x| res << x}
    assert_equal([S("")], res)

    res = []
    S("a\n b\n").each_line(" ", chomp: true) {|x| res << x}
    assert_equal([S("a\n"), S("b\n")], res)
  end

  def test_lines
    s = S("hello\nworld")
    assert_equal ["hello\n", "world"], s.lines
    assert_equal ["hello\nworld"], s.lines(nil)

    res = []
    assert_equal s.object_id, s.lines {|x| res << x }.object_id
    assert_equal(S("hello\n"), res[0])
    assert_equal(S("world"),  res[1])
  end

  def test_empty?
    assert_empty(S(""))
    assert_not_empty(S("not"))
  end

  def test_end_with?
    assert_send([S("hello"), :end_with?, S("llo")])
    assert_not_send([S("hello"), :end_with?, S("ll")])
    assert_send([S("hello"), :end_with?, S("el"), S("lo")])
    assert_send([S("hello"), :end_with?, S("")])
    assert_not_send([S("hello"), :end_with?])

    bug5536 = '[ruby-core:40623]'
    assert_raise(TypeError, bug5536) {S("str").end_with? :not_convertible_to_string}
  end

  def test_eql?
    a = S("hello")
    assert_operator(a, :eql?, S("hello"))
    assert_operator(a, :eql?, a)
  end

  def test_gsub
    assert_equal(S("h*ll*"),     S("hello").gsub(/[aeiou]/, S('*')))
    assert_equal(S("h<e>ll<o>"), S("hello").gsub(/([aeiou])/, S('<\1>')))
    assert_equal(S("h e l l o "),
                 S("hello").gsub(/./) { |s| s[0].to_s + S(' ')})
    assert_equal(S("HELL-o"),
                 S("hello").gsub(/(hell)(.)/) { |s| $1.upcase + S('-') + $2 })
    assert_equal(S("<>h<>e<>l<>l<>o<>"), S("hello").gsub(S(''), S('<\0>')))

    assert_equal("z", S("abc").gsub(/./, "a" => "z"), "moved from btest/knownbug")

    assert_raise(ArgumentError) { S("foo").gsub }
  end

  def test_gsub_encoding
    a = S("hello world")
    a.force_encoding Encoding::UTF_8

    b = S("hi")
    b.force_encoding Encoding::US_ASCII

    assert_equal Encoding::UTF_8, a.gsub(/hello/, b).encoding

    c = S("everybody")
    c.force_encoding Encoding::US_ASCII

    assert_equal Encoding::UTF_8, a.gsub(/world/, c).encoding

    assert_equal S("a\u{e9}apos&lt;"), S("a\u{e9}'&lt;").gsub("'", "apos")

    bug9849 = '[ruby-core:62669] [Bug #9849]'
    assert_equal S("\u{3042 3042 3042}!foo!"), S("\u{3042 3042 3042}/foo/").gsub("/", "!"), bug9849
  end

  def test_gsub!
    a = S("hello")
    b = a.dup
    a.gsub!(/[aeiou]/, S('*'))
    assert_equal(S("h*ll*"), a)
    assert_equal(S("hello"), b)

    a = S("hello")
    a.gsub!(/([aeiou])/, S('<\1>'))
    assert_equal(S("h<e>ll<o>"), a)

    a = S("hello")
    a.gsub!(/./) { |s| s[0].to_s + S(' ')}
    assert_equal(S("h e l l o "), a)

    a = S("hello")
    a.gsub!(/(hell)(.)/) { |s| $1.upcase + S('-') + $2 }
    assert_equal(S("HELL-o"), a)

    a = S("hello")
    assert_nil(a.sub!(S('X'), S('Y')))
  end

  def test_sub_hash
    assert_equal('azc', S('abc').sub(/b/, "b" => "z"))
    assert_equal('ac', S('abc').sub(/b/, {}))
    assert_equal('a1c', S('abc').sub(/b/, "b" => 1))
    assert_equal('aBc', S('abc').sub(/b/, Hash.new {|h, k| k.upcase }))
    assert_equal('a[\&]c', S('abc').sub(/b/, "b" => '[\&]'))
    assert_equal('aBcabc', S('abcabc').sub(/b/, Hash.new {|h, k| h[k] = k.upcase }))
    assert_equal('aBcdef', S('abcdef').sub(/de|b/, "b" => "B", "de" => "DE"))
  end

  def test_gsub_hash
    assert_equal('azc', S('abc').gsub(/b/, "b" => "z"))
    assert_equal('ac', S('abc').gsub(/b/, {}))
    assert_equal('a1c', S('abc').gsub(/b/, "b" => 1))
    assert_equal('aBc', S('abc').gsub(/b/, Hash.new {|h, k| k.upcase }))
    assert_equal('a[\&]c', S('abc').gsub(/b/, "b" => '[\&]'))
    assert_equal('aBcaBc', S('abcabc').gsub(/b/, Hash.new {|h, k| h[k] = k.upcase }))
    assert_equal('aBcDEf', S('abcdef').gsub(/de|b/, "b" => "B", "de" => "DE"))
  end

  def test_hash
    assert_equal(S("hello").hash, S("hello").hash)
    assert_not_equal(S("hello").hash, S("helLO").hash)
    bug4104 = '[ruby-core:33500]'
    assert_not_equal(S("a").hash, S("a\0").hash, bug4104)
    bug9172 = '[ruby-core:58658] [Bug #9172]'
    assert_not_equal(S("sub-setter").hash, S("discover").hash, bug9172)
  end

  def test_hex
    assert_equal(255,  S("0xff").hex)
    assert_equal(-255, S("-0xff").hex)
    assert_equal(255,  S("ff").hex)
    assert_equal(-255, S("-ff").hex)
    assert_equal(0,    S("-ralph").hex)
    assert_equal(-15,  S("-fred").hex)
    assert_equal(15,   S("fred").hex)
  end

  def test_include?
    assert_include(S("foobar"), ?f)
    assert_include(S("foobar"), S("foo"))
    assert_not_include(S("foobar"), S("baz"))
    assert_not_include(S("foobar"), ?z)
  end

  def test_index
    assert_equal(0, S("hello").index(?h))
    assert_equal(1, S("hello").index(S("ell")))
    assert_equal(2, S("hello").index(/ll./))

    assert_equal(3, S("hello").index(?l, 3))
    assert_equal(3, S("hello").index(S("l"), 3))
    assert_equal(3, S("hello").index(/l./, 3))

    assert_nil(S("hello").index(?z, 3))
    assert_nil(S("hello").index(S("z"), 3))
    assert_nil(S("hello").index(/z./, 3))

    assert_nil(S("hello").index(?z))
    assert_nil(S("hello").index(S("z")))
    assert_nil(S("hello").index(/z./))

    assert_equal(0, S("").index(S("")))
    assert_equal(0, S("").index(//))
    assert_nil(S("").index(S("hello")))
    assert_nil(S("").index(/hello/))
    assert_equal(0, S("hello").index(S("")))
    assert_equal(0, S("hello").index(//))

    s = S("long") * 1000 << "x"
    assert_nil(s.index(S("y")))
    assert_equal(4 * 1000, s.index(S("x")))
    s << "yx"
    assert_equal(4 * 1000, s.index(S("x")))
    assert_equal(4 * 1000, s.index(S("xyx")))

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal(3, S("foobarbarbaz").index(o))
    assert_raise(TypeError) { S("foo").index(Object.new) }

    assert_nil(S("foo").index(//, -100))
    assert_nil($~)

    assert_equal(2, S("abcdbce").index(/b\Kc/))

    assert_equal(0, S("こんにちは").index(?こ))
    assert_equal(1, S("こんにちは").index(S("んにち")))
    assert_equal(2, S("こんにちは").index(/にち./))

    assert_equal(0, S("にんにちは").index(?に, 0))
    assert_equal(2, S("にんにちは").index(?に, 1))
    assert_equal(2, S("にんにちは").index(?に, 2))
    assert_nil(S("にんにちは").index(?に, 3))
  end

  def test_insert
    assert_equal("Xabcd", S("abcd").insert(0, 'X'))
    assert_equal("abcXd", S("abcd").insert(3, 'X'))
    assert_equal("abcdX", S("abcd").insert(4, 'X'))
    assert_equal("abXcd", S("abcd").insert(-3, 'X'))
    assert_equal("abcdX", S("abcd").insert(-1, 'X'))
  end

  def test_intern
    assert_equal(:koala, S("koala").intern)
    assert_not_equal(:koala, S("Koala").intern)
  end

  def test_length
    assert_equal(0, S("").length)
    assert_equal(4, S("1234").length)
    assert_equal(6, S("1234\r\n").length)
    assert_equal(7, S("\0011234\r\n").length)
  end

  def test_ljust
    assert_equal(S("hello"),       S("hello").ljust(4))
    assert_equal(S("hello      "), S("hello").ljust(11))
    assert_equal(S("ababababab"), S("").ljust(10, "ab"), Bug2463)
    assert_equal(S("abababababa"), S("").ljust(11, "ab"), Bug2463)
  end

  def test_next
    assert_equal(S("abd"), S("abc").next)
    assert_equal(S("z"),   S("y").next)
    assert_equal(S("aaa"), S("zz").next)

    assert_equal(S("124"),  S("123").next)
    assert_equal(S("1000"), S("999").next)

    assert_equal(S("2000aaa"),  S("1999zzz").next)
    assert_equal(S("AAAAA000"), S("ZZZZ999").next)

    assert_equal(S("*+"), S("**").next)

    assert_equal(S("!"), S(" ").next)
    assert_equal(S(""), S("").next)
  end

  def test_next!
    a = S("abc")
    b = a.dup
    assert_equal(S("abd"), a.next!)
    assert_equal(S("abd"), a)
    assert_equal(S("abc"), b)

    a = S("y")
    assert_equal(S("z"), a.next!)
    assert_equal(S("z"), a)

    a = S("zz")
    assert_equal(S("aaa"), a.next!)
    assert_equal(S("aaa"), a)

    a = S("123")
    assert_equal(S("124"), a.next!)
    assert_equal(S("124"), a)

    a = S("999")
    assert_equal(S("1000"), a.next!)
    assert_equal(S("1000"), a)

    a = S("1999zzz")
    assert_equal(S("2000aaa"), a.next!)
    assert_equal(S("2000aaa"), a)

    a = S("ZZZZ999")
    assert_equal(S("AAAAA000"), a.next!)
    assert_equal(S("AAAAA000"), a)

    a = S("**")
    assert_equal(S("*+"), a.next!)
    assert_equal(S("*+"), a)

    a = S(" ")
    assert_equal(S("!"), a.next!)
    assert_equal(S("!"), a)
  end

  def test_oct
    assert_equal(255,  S("0377").oct)
    assert_equal(255,  S("377").oct)
    assert_equal(-255, S("-0377").oct)
    assert_equal(-255, S("-377").oct)
    assert_equal(0,    S("OO").oct)
    assert_equal(24,   S("030OO").oct)
  end

  def test_replace
    a = S("foo")
    assert_equal(S("f"), a.replace(S("f")))

    a = S("foo")
    assert_equal(S("foobar"), a.replace(S("foobar")))

    a = S("foo")
    b = a.replace(S("xyz"))
    assert_equal(S("xyz"), b)

    s = S("foo") * 100
    s2 = ("bar" * 100).dup
    s.replace(s2)
    assert_equal(s2, s)

    s2 = [S("foo")].pack("p")
    s.replace(s2)
    assert_equal(s2, s)

    fs = S("").freeze
    assert_raise(FrozenError) { fs.replace("a") }
    assert_raise(FrozenError) { fs.replace(fs) }
    assert_raise(ArgumentError) { fs.replace() }
    assert_raise(FrozenError) { fs.replace(42) }
  end

  def test_reverse
    assert_equal(S("beta"), S("ateb").reverse)
    assert_equal(S("madamImadam"), S("madamImadam").reverse)

    a=S("beta")
    assert_equal(S("ateb"), a.reverse)
    assert_equal(S("beta"), a)
  end

  def test_reverse!
    a = S("beta")
    b = a.dup
    assert_equal(S("ateb"), a.reverse!)
    assert_equal(S("ateb"), a)
    assert_equal(S("beta"), b)

    assert_equal(S("madamImadam"), S("madamImadam").reverse!)

    a = S("madamImadam")
    assert_equal(S("madamImadam"), a.reverse!)  # ??
    assert_equal(S("madamImadam"), a)
  end

  def test_rindex
    assert_equal(3, S("hello").rindex(?l))
    assert_equal(6, S("ell, hello").rindex(S("ell")))
    assert_equal(7, S("ell, hello").rindex(/ll./))

    assert_equal(3, S("hello,lo").rindex(?l, 3))
    assert_equal(3, S("hello,lo").rindex(S("l"), 3))
    assert_equal(3, S("hello,lo").rindex(/l./, 3))

    assert_nil(S("hello").rindex(?z,     3))
    assert_nil(S("hello").rindex(S("z"), 3))
    assert_nil(S("hello").rindex(/z./,   3))

    assert_nil(S("hello").rindex(?z))
    assert_nil(S("hello").rindex(S("z")))
    assert_nil(S("hello").rindex(/z./))

    assert_equal(5, S("hello").rindex(S("")))
    assert_equal(5, S("hello").rindex(S(""), 5))
    assert_equal(4, S("hello").rindex(S(""), 4))
    assert_equal(0, S("hello").rindex(S(""), 0))

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal(6, S("foobarbarbaz").rindex(o))
    assert_raise(TypeError) { S("foo").rindex(Object.new) }

    assert_nil(S("foo").rindex(//, -100))
    assert_nil($~)

    assert_equal(3, S("foo").rindex(//))
    assert_equal([3, 3], $~.offset(0))

    assert_equal(5, S("abcdbce").rindex(/b\Kc/))

    assert_equal(2, S("こんにちは").rindex(?に))
    assert_equal(6, S("にちは、こんにちは").rindex(S("にちは")))
    assert_equal(6, S("にちは、こんにちは").rindex(/にち./))

    assert_equal(6, S("にちは、こんにちは").rindex(S("にちは"), 7))
    assert_equal(6, S("にちは、こんにちは").rindex(S("にちは"), -2))
    assert_equal(6, S("にちは、こんにちは").rindex(S("にちは"), 6))
    assert_equal(6, S("にちは、こんにちは").rindex(S("にちは"), -3))
    assert_equal(0, S("にちは、こんにちは").rindex(S("にちは"), 5))
    assert_equal(0, S("にちは、こんにちは").rindex(S("にちは"), -4))
    assert_equal(0, S("にちは、こんにちは").rindex(S("にちは"), 1))
    assert_equal(0, S("にちは、こんにちは").rindex(S("にちは"), 0))

    assert_equal(0, S("こんにちは").rindex(S("こんにちは")))
    assert_nil(S("こんにち").rindex(S("こんにちは")))
    assert_nil(S("こ").rindex(S("こんにちは")))
    assert_nil(S("").rindex(S("こんにちは")))
  end

  def test_rjust
    assert_equal(S("hello"), S("hello").rjust(4))
    assert_equal(S("      hello"), S("hello").rjust(11))
    assert_equal(S("ababababab"), S("").rjust(10, "ab"), Bug2463)
    assert_equal(S("abababababa"), S("").rjust(11, "ab"), Bug2463)
  end

  def test_scan
    a = S("cruel world")
    assert_equal([S("cruel"), S("world")],a.scan(/\w+/))
    assert_equal([S("cru"), S("el "), S("wor")],a.scan(/.../))
    assert_equal([[S("cru")], [S("el ")], [S("wor")]],a.scan(/(...)/))

    res = []
    a.scan(/\w+/) { |w| res << w }
    assert_equal([S("cruel"), S("world") ],res)

    res = []
    a.scan(/.../) { |w| res << w }
    assert_equal([S("cru"), S("el "), S("wor")],res)

    res = []
    a.scan(/(...)/) { |w| res << w }
    assert_equal([[S("cru")], [S("el ")], [S("wor")]],res)

    /h/ =~ a
    a.scan(/x/)
    assert_nil($~)

    /h/ =~ a
    a.scan('x')
    assert_nil($~)

    assert_equal(%w[1 2 3], S("a1 a2 a3").scan(/a\K./))
  end

  def test_scan_segv
    bug19159 = '[Bug #19159]'
    assert_nothing_raised(Exception, bug19159) do
      ObjectSpace.each_object(MatchData).to_a
      "".scan(//)
      ObjectSpace.each_object(MatchData).to_a.inspect
    end
  end

  def test_size
    assert_equal(0, S("").size)
    assert_equal(4, S("1234").size)
    assert_equal(6, S("1234\r\n").size)
    assert_equal(7, S("\0011234\r\n").size)
  end

  def test_slice
    assert_equal(?A, S("AooBar").slice(0))
    assert_equal(?B, S("FooBaB").slice(-1))
    assert_nil(S("FooBar").slice(6))
    assert_nil(S("FooBar").slice(-7))

    assert_equal(S("Foo"), S("FooBar").slice(0,3))
    assert_equal(S(S("Bar")), S("FooBar").slice(-3,3))
    assert_nil(S("FooBar").slice(7,2))     # Maybe should be six?
    assert_nil(S("FooBar").slice(-7,10))

    assert_equal(S("Foo"), S("FooBar").slice(0..2))
    assert_equal(S("Bar"), S("FooBar").slice(-3..-1))
    assert_equal(S(""), S("FooBar").slice(6..2))
    assert_nil(S("FooBar").slice(-10..-7))

    assert_equal(S("Foo"), S("FooBar").slice(/^F../))
    assert_equal(S("Bar"), S("FooBar").slice(/..r$/))
    assert_nil(S("FooBar").slice(/xyzzy/))
    assert_nil(S("FooBar").slice(/plugh/))

    assert_equal(S("Foo"), S("FooBar").slice(S("Foo")))
    assert_equal(S("Bar"), S("FooBar").slice(S("Bar")))
    assert_nil(S("FooBar").slice(S("xyzzy")))
    assert_nil(S("FooBar").slice(S("plugh")))

    bug9882 = '[ruby-core:62842] [Bug #9882]'
    substr = S("\u{30c6 30b9 30c8 2019}#{bug9882}").slice(4..-1)
    assert_equal(S(bug9882).hash, substr.hash, bug9882)
    assert_predicate(substr, :ascii_only?, bug9882)
  end

  def test_slice!
    a = S("AooBar")
    b = a.dup
    assert_equal(?A, a.slice!(0))
    assert_equal(S("ooBar"), a)
    assert_equal(S("AooBar"), b)

    a = S("FooBar")
    assert_equal(?r,a.slice!(-1))
    assert_equal(S("FooBa"), a)

    a = S("FooBar")
    if @aref_slicebang_silent
      assert_nil( a.slice!(6) )
      assert_nil( a.slice!(6r) )
    else
      assert_raise(IndexError) { a.slice!(6) }
      assert_raise(IndexError) { a.slice!(6r) }
    end
    assert_equal(S("FooBar"), a)

    if @aref_slicebang_silent
      assert_nil( a.slice!(-7) )
    else
      assert_raise(IndexError) { a.slice!(-7) }
    end
    assert_equal(S("FooBar"), a)

    a = S("FooBar")
    assert_equal(S("Foo"), a.slice!(0,3))
    assert_equal(S("Bar"), a)

    a = S("FooBar")
    assert_equal(S("Bar"), a.slice!(-3,3))
    assert_equal(S("Foo"), a)

    a=S("FooBar")
    if @aref_slicebang_silent
    assert_nil(a.slice!(7,2))      # Maybe should be six?
    else
    assert_raise(IndexError) {a.slice!(7,2)}     # Maybe should be six?
    end
    assert_equal(S("FooBar"), a)
    if @aref_slicebang_silent
    assert_nil(a.slice!(-7,10))
    else
    assert_raise(IndexError) {a.slice!(-7,10)}
    end
    assert_equal(S("FooBar"), a)

    a=S("FooBar")
    assert_equal(S("Foo"), a.slice!(0..2))
    assert_equal(S("Bar"), a)

    a=S("FooBar")
    assert_equal(S("Bar"), a.slice!(-3..-1))
    assert_equal(S("Foo"), a)

    a=S("FooBar")
    if @aref_slicebang_silent
    assert_equal(S(""), a.slice!(6..2))
    else
    assert_raise(RangeError) {a.slice!(6..2)}
    end
    assert_equal(S("FooBar"), a)
    if @aref_slicebang_silent
    assert_nil(a.slice!(-10..-7))
    else
    assert_raise(RangeError) {a.slice!(-10..-7)}
    end
    assert_equal(S("FooBar"), a)

    a=S("FooBar")
    assert_equal(S("Foo"), a.slice!(/^F../))
    assert_equal(S("Bar"), a)

    a=S("FooBar")
    assert_equal(S("Bar"), a.slice!(/..r$/))
    assert_equal(S("Foo"), a)

    a=S("FooBar")
    if @aref_slicebang_silent
      assert_nil(a.slice!(/xyzzy/))
    else
      assert_raise(IndexError) {a.slice!(/xyzzy/)}
    end
    assert_equal(S("FooBar"), a)
    if @aref_slicebang_silent
      assert_nil(a.slice!(/plugh/))
    else
      assert_raise(IndexError) {a.slice!(/plugh/)}
    end
    assert_equal(S("FooBar"), a)

    a=S("FooBar")
    assert_equal(S("Foo"), a.slice!(S("Foo")))
    assert_equal(S("Bar"), a)

    a=S("FooBar")
    assert_equal(S("Bar"), a.slice!(S("Bar")))
    assert_equal(S("Foo"), a)

    a = S("foo")
    assert_raise(ArgumentError) { a.slice! }
  end

  def test_split
    fs, $; = $;, nil
    assert_equal([S("a"), S("b"), S("c")], S(" a   b\t c ").split)
    assert_equal([S("a"), S("b"), S("c")], S(" a   b\t c ").split(S(" ")))

    assert_equal([S(" a "), S(" b "), S(" c ")], S(" a | b | c ").split(S("|")))

    assert_equal([S("a"), S("b"), S("c")], S("aXXbXXcXX").split(/X./))

    assert_equal([S("a"), S("b"), S("c")], S("abc").split(//))

    assert_equal([S("a|b|c")], S("a|b|c").split(S('|'), 1))

    assert_equal([S("a"), S("b|c")], S("a|b|c").split(S('|'), 2))
    assert_equal([S("a"), S("b"), S("c")], S("a|b|c").split(S('|'), 3))

    assert_equal([S("a"), S("b"), S("c"), S("")], S("a|b|c|").split(S('|'), -1))
    assert_equal([S("a"), S("b"), S("c"), S(""), S("")], S("a|b|c||").split(S('|'), -1))

    assert_equal([S("a"), S(""), S("b"), S("c")], S("a||b|c|").split(S('|')))
    assert_equal([S("a"), S(""), S("b"), S("c"), S("")], S("a||b|c|").split(S('|'), -1))

    assert_equal([], S("").split(//, 1))
  ensure
    EnvUtil.suppress_warning {$; = fs}
  end

  def test_split_with_block
    fs, $; = $;, nil
    result = []; S(" a   b\t c ").split {|s| result << s}
    assert_equal([S("a"), S("b"), S("c")], result)
    result = []; S(" a   b\t c ").split(S(" ")) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c")], result)

    result = []; S(" a | b | c ").split(S("|")) {|s| result << s}
    assert_equal([S(" a "), S(" b "), S(" c ")], result)

    result = []; S("aXXbXXcXX").split(/X./) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c")], result)

    result = []; S("abc").split(//) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c")], result)

    result = []; S("a|b|c").split(S('|'), 1) {|s| result << s}
    assert_equal([S("a|b|c")], result)

    result = []; S("a|b|c").split(S('|'), 2) {|s| result << s}
    assert_equal([S("a"), S("b|c")], result)
    result = []; S("a|b|c").split(S('|'), 3) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c")], result)

    result = []; S("a|b|c|").split(S('|'), -1) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c"), S("")], result)
    result = []; S("a|b|c||").split(S('|'), -1) {|s| result << s}
    assert_equal([S("a"), S("b"), S("c"), S(""), S("")], result)

    result = []; S("a||b|c|").split(S('|')) {|s| result << s}
    assert_equal([S("a"), S(""), S("b"), S("c")], result)
    result = []; S("a||b|c|").split(S('|'), -1) {|s| result << s}
    assert_equal([S("a"), S(""), S("b"), S("c"), S("")], result)

    result = []; S("").split(//, 1) {|s| result << s}
    assert_equal([], result)

    result = []; S("aaa,bbb,ccc,ddd").split(/,/) {|s| result << s.gsub(/./, "A")}
    assert_equal(["AAA"]*4, result)
  ensure
    EnvUtil.suppress_warning {$; = fs}
  end

  def test_fs
    return unless @cls == String

    assert_raise_with_message(TypeError, /\$;/) {
      $; = []
    }

    assert_separately(%W[-W0], "#{<<~"begin;"}\n#{<<~'end;'}")
    bug = '[ruby-core:79582] $; must not be GCed'
    begin;
      $; = " "
      $a = nil
      alias $; $a
      alias $-F $a
      GC.start
      assert_equal([], "".split, bug)
    end;
  end

  def test_split_encoding
    bug6206 = '[ruby-dev:45441]'
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      s = S("a:".force_encoding(enc))
      assert_equal([enc]*2, s.split(":", 2).map(&:encoding), bug6206)
    end
  end

  def test_split_wchar
    bug8642 = '[ruby-core:56036] [Bug #8642]'
    WIDE_ENCODINGS.each do |enc|
      s = S("abc,def".encode(enc))
      assert_equal(["abc", "def"].map {|c| c.encode(enc)},
                   s.split(",".encode(enc)),
                   "#{bug8642} in #{enc.name}")
    end
  end

  def test_split_invalid_sequence
    bug10886 = '[ruby-core:68229] [Bug #10886]'
    broken = S("\xa1".force_encoding("utf-8"))
    assert_raise(ArgumentError, bug10886) {
      S("a,b").split(broken)
    }
  end

  def test_split_invalid_argument
    assert_raise(TypeError) {
      S("a,b").split(BasicObject.new)
    }
  end

  def test_split_dupped
    s = "abc"
    s.split("b", 1).map(&:upcase!)
    assert_equal("abc", s)
  end

  def test_split_lookbehind
    assert_equal([S("ab"), S("d")], S("abcd").split(/(?<=b)c/))
    assert_equal([S("ab"), S("d")], S("abcd").split(/b\Kc/))
  end

  def test_squeeze
    assert_equal(S("abc"), S("aaabbbbccc").squeeze)
    assert_equal(S("aa bb cc"), S("aa   bb      cc").squeeze(S(" ")))
    assert_equal(S("BxTyWz"), S("BxxxTyyyWzzzzz").squeeze(S("a-z")))
  end

  def test_squeeze!
    a = S("aaabbbbccc")
    b = a.dup
    assert_equal(S("abc"), a.squeeze!)
    assert_equal(S("abc"), a)
    assert_equal(S("aaabbbbccc"), b)

    a = S("aa   bb      cc")
    assert_equal(S("aa bb cc"), a.squeeze!(S(" ")))
    assert_equal(S("aa bb cc"), a)

    a = S("BxxxTyyyWzzzzz")
    assert_equal(S("BxTyWz"), a.squeeze!(S("a-z")))
    assert_equal(S("BxTyWz"), a)

    a=S("The quick brown fox")
    assert_nil(a.squeeze!)
  end

  def test_start_with?
    assert_send([S("hello"), :start_with?, S("hel")])
    assert_not_send([S("hello"), :start_with?, S("el")])
    assert_send([S("hello"), :start_with?, S("el"), S("he")])

    bug5536 = '[ruby-core:40623]'
    assert_raise(TypeError, bug5536) {S("str").start_with? :not_convertible_to_string}

    assert_equal(true, S("hello").start_with?(/hel/))
    assert_equal("hel", $&)
    assert_equal(false, S("hello").start_with?(/el/))
    assert_nil($&)
  end

  def test_strip
    assert_equal(S("x"), S("      x        ").strip)
    assert_equal(S("x"), S(" \n\r\t     x  \t\r\n\n      ").strip)
    assert_equal(S("x"), S("\x00x\x00").strip)

    assert_equal("0b0 ".force_encoding("UTF-16BE"),
                 S("\x00 0b0 ").force_encoding("UTF-16BE").strip)
    assert_equal("0\x000b0 ".force_encoding("UTF-16BE"),
                 S("0\x000b0 ").force_encoding("UTF-16BE").strip)
  end

  def test_strip!
    a = S("      x        ")
    b = a.dup
    assert_equal(S("x") ,a.strip!)
    assert_equal(S("x") ,a)
    assert_equal(S("      x        "), b)

    a = S(" \n\r\t     x  \t\r\n\n      ")
    assert_equal(S("x"), a.strip!)
    assert_equal(S("x"), a)

    a = S("\x00x\x00")
    assert_equal(S("x"), a.strip!)
    assert_equal(S("x"), a)

    a = S("x")
    assert_nil(a.strip!)
    assert_equal(S("x") ,a)
  end

  def test_sub
    assert_equal(S("h*llo"),    S("hello").sub(/[aeiou]/, S('*')))
    assert_equal(S("h<e>llo"),  S("hello").sub(/([aeiou])/, S('<\1>')))
    assert_equal(S("h ello"), S("hello").sub(/./) {
                   |s| s[0].to_s + S(' ')})
    assert_equal(S("HELL-o"),   S("hello").sub(/(hell)(.)/) {
                   |s| $1.upcase + S('-') + $2
                   })
    assert_equal(S("h<e>llo"),  S("hello").sub('e', S('<\0>')))

    assert_equal(S("a\\aba"), S("ababa").sub(/b/, '\\'))
    assert_equal(S("ab\\aba"), S("ababa").sub(/(b)/, '\1\\'))
    assert_equal(S("ababa"), S("ababa").sub(/(b)/, '\1'))
    assert_equal(S("ababa"), S("ababa").sub(/(b)/, '\\1'))
    assert_equal(S("a\\1aba"), S("ababa").sub(/(b)/, '\\\1'))
    assert_equal(S("a\\1aba"), S("ababa").sub(/(b)/, '\\\\1'))
    assert_equal(S("a\\baba"), S("ababa").sub(/(b)/, '\\\\\1'))

    assert_equal(S("a--ababababababababab"),
		 S("abababababababababab").sub(/(b)/, '-\9-'))
    assert_equal(S("1-b-0"),
		 S("1b2b3b4b5b6b7b8b9b0").
		 sub(/(b).(b).(b).(b).(b).(b).(b).(b).(b)/, '-\9-'))
    assert_equal(S("1-b-0"),
		 S("1b2b3b4b5b6b7b8b9b0").
		 sub(/(b).(b).(b).(b).(b).(b).(b).(b).(b)/, '-\\9-'))
    assert_equal(S("1-\\9-0"),
		 S("1b2b3b4b5b6b7b8b9b0").
		 sub(/(b).(b).(b).(b).(b).(b).(b).(b).(b)/, '-\\\9-'))
    assert_equal(S("k"),
		 S("1a2b3c4d5e6f7g8h9iAjBk").
		 sub(/.(.).(.).(.).(.).(.).(.).(.).(.).(.).(.).(.)/, '\+'))

    assert_equal(S("ab\\aba"), S("ababa").sub(/b/, '\&\\'))
    assert_equal(S("ababa"), S("ababa").sub(/b/, '\&'))
    assert_equal(S("ababa"), S("ababa").sub(/b/, '\\&'))
    assert_equal(S("a\\&aba"), S("ababa").sub(/b/, '\\\&'))
    assert_equal(S("a\\&aba"), S("ababa").sub(/b/, '\\\\&'))
    assert_equal(S("a\\baba"), S("ababa").sub(/b/, '\\\\\&'))

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal("fooBARbaz", S("foobarbaz").sub(o, "BAR"))

    assert_raise(TypeError) { S("foo").sub(Object.new, "") }

    assert_raise(ArgumentError) { S("foo").sub }

    assert_raise(IndexError) { "foo"[/(?:(o$)|(x))/, 2] = 'bar' }

    o = Object.new
    def o.to_s; self; end
    assert_match(/^foo#<Object:0x.*>baz$/, S("foobarbaz").sub("bar") { o })

    assert_equal(S("Abc"), S("abc").sub("a", "A"))
    m = nil
    assert_equal(S("Abc"), S("abc").sub("a") {m = $~; "A"})
    assert_equal(S("a"), m[0])
    assert_equal(/a/, m.regexp)
    bug = '[ruby-core:78686] [Bug #13042] other than regexp has no name references'
    assert_raise_with_message(IndexError, /oops/, bug) {
      S('hello').gsub('hello', '\k<oops>')
    }
  end

  def test_sub!
    a = S("hello")
    b = a.dup
    a.sub!(/[aeiou]/, S('*'))
    assert_equal(S("h*llo"), a)
    assert_equal(S("hello"), b)

    a = S("hello")
    a.sub!(/([aeiou])/, S('<\1>'))
    assert_equal(S("h<e>llo"), a)

    a = S("hello")
    a.sub!(/./) { |s| s[0].to_s + S(' ')}
    assert_equal(S("h ello"), a)

    a = S("hello")
    a.sub!(/(hell)(.)/) { |s| $1.upcase + S('-') + $2 }
    assert_equal(S("HELL-o"), a)

    a=S("hello")
    assert_nil(a.sub!(/X/, S('Y')))

    bug16105 = '[Bug #16105] heap-use-after-free'
    a = S("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345678")
    b = a.dup
    c = a.slice(1, 100)
    assert_equal("AABCDEFGHIJKLMNOPQRSTUVWXYZ012345678", b.sub!(c, b), bug16105)
  end

  def test_succ
    assert_equal(S("abd"), S("abc").succ)
    assert_equal(S("z"),   S("y").succ)
    assert_equal(S("aaa"), S("zz").succ)

    assert_equal(S("124"),  S("123").succ)
    assert_equal(S("1000"), S("999").succ)
    assert_equal(S("2.000"), S("1.999").succ)

    assert_equal(S("No.10"), S("No.9").succ)
    assert_equal(S("2000aaa"),  S("1999zzz").succ)
    assert_equal(S("AAAAA000"), S("ZZZZ999").succ)
    assert_equal(S("*+"), S("**").succ)

    assert_equal("abce", S("abcd").succ)
    assert_equal("THX1139", S("THX1138").succ)
    assert_equal("<\<koalb>>", S("<\<koala>>").succ)
    assert_equal("2000aaa", S("1999zzz").succ)
    assert_equal("AAAA0000", S("ZZZ9999").succ)
    assert_equal("**+", S("***").succ)

    assert_equal("!", S(" ").succ)
    assert_equal("", S("").succ)

    bug = '[ruby-core:83062] [Bug #13952]'
    s = S("\xff").b
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.succ, :ascii_only?, bug)
  end

  def test_succ!
    a = S("abc")
    b = a.dup
    assert_equal(S("abd"), a.succ!)
    assert_equal(S("abd"), a)
    assert_equal(S("abc"), b)

    a = S("y")
    assert_equal(S("z"), a.succ!)
    assert_equal(S("z"), a)

    a = S("zz")
    assert_equal(S("aaa"), a.succ!)
    assert_equal(S("aaa"), a)

    a = S("123")
    assert_equal(S("124"), a.succ!)
    assert_equal(S("124"), a)

    a = S("999")
    assert_equal(S("1000"), a.succ!)
    assert_equal(S("1000"), a)

    a = S("1999zzz")
    assert_equal(S("2000aaa"), a.succ!)
    assert_equal(S("2000aaa"), a)

    a = S("ZZZZ999")
    assert_equal(S("AAAAA000"), a.succ!)
    assert_equal(S("AAAAA000"), a)

    a = S("**")
    assert_equal(S("*+"), a.succ!)
    assert_equal(S("*+"), a)

    a = S("No.9")
    assert_equal(S("No.10"), a.succ!)
    assert_equal(S("No.10"), a)

    a = S(" ")
    assert_equal(S("!"), a.succ!)
    assert_equal(S("!"), a)

    a = S("")
    assert_equal(S(""), a.succ!)
    assert_equal(S(""), a)

    assert_equal("aaaaaaaaaaaa", S("zzzzzzzzzzz").succ!)
    assert_equal("aaaaaaaaaaaaaaaaaaaaaaaa", S("zzzzzzzzzzzzzzzzzzzzzzz").succ!)
  end

  def test_sum
    n = S("\001\001\001\001\001\001\001\001\001\001\001\001\001\001\001")
    assert_equal(15, n.sum)
    n += S("\001")
    assert_equal(16, n.sum(17))
    n[0] = 2.chr
    assert_not_equal(15, n.sum)
    assert_equal(17, n.sum(0))
    assert_equal(17, n.sum(-1))
  end

  def check_sum(str, bits=16)
    sum = 0
    str.each_byte {|c| sum += c}
    sum = sum & ((1 << bits) - 1) if bits != 0
    assert_equal(sum, str.sum(bits))
  end

  def test_sum_2
    assert_equal(0, S("").sum)
    assert_equal(294, S("abc").sum)
    check_sum("abc")
    check_sum("\x80")
    -3.upto(70) {|bits|
      check_sum("xyz", bits)
    }
  end

  def test_sum_long
    s8421505 = "\xff" * 8421505
    assert_equal(127, s8421505.sum(31))
    assert_equal(2147483775, s8421505.sum(0))
    s16843010 = ("\xff" * 16843010)
    assert_equal(254, s16843010.sum(32))
    assert_equal(4294967550, s16843010.sum(0))
  end

  def test_swapcase
    assert_equal(S("hi&LOW"), S("HI&low").swapcase)
    s = S("")
    assert_not_same(s, s.swapcase)
  end

  def test_swapcase!
    a = S("hi&LOW")
    b = a.dup
    assert_equal(S("HI&low"), a.swapcase!)
    assert_equal(S("HI&low"), a)
    assert_equal(S("hi&LOW"), b)

    a = S("$^#^%$#!!")
    assert_nil(a.swapcase!)
    assert_equal(S("$^#^%$#!!"), a)
  end

  def test_to_f
    assert_equal(344.3,     S("344.3").to_f)
    assert_equal(5.9742e24, S("5.9742e24").to_f)
    assert_equal(98.6,      S("98.6 degrees").to_f)
    assert_equal(0.0,       S("degrees 100.0").to_f)
    assert_equal([ 0.0].pack('G'), [S(" 0.0").to_f].pack('G'))
    assert_equal([-0.0].pack('G'), [S("-0.0").to_f].pack('G'))
  end

  def test_to_i
    assert_equal(1480, S("1480ft/sec").to_i)
    assert_equal(0,    S("speed of sound in water @20C = 1480ft/sec)").to_i)
    assert_equal(0, S(" 0").to_i)
    assert_equal(0, S("+0").to_i)
    assert_equal(0, S("-0").to_i)
    assert_equal(0, S("--0").to_i)
    assert_equal(16, S("0x10").to_i(0))
    assert_equal(16, S("0X10").to_i(0))
    assert_equal(2, S("0b10").to_i(0))
    assert_equal(2, S("0B10").to_i(0))
    assert_equal(8, S("0o10").to_i(0))
    assert_equal(8, S("0O10").to_i(0))
    assert_equal(10, S("0d10").to_i(0))
    assert_equal(10, S("0D10").to_i(0))
    assert_equal(8, S("010").to_i(0))
    assert_raise(ArgumentError) { S("010").to_i(-10) }
    2.upto(36) {|radix|
      assert_equal(radix, S("10").to_i(radix))
      assert_equal(radix**2, S("100").to_i(radix))
    }
    assert_raise(ArgumentError) { S("0").to_i(1) }
    assert_raise(ArgumentError) { S("0").to_i(37) }
    assert_equal(0, S("z").to_i(10))
    assert_equal(12, S("1_2").to_i(10))
    assert_equal(0x40000000, S("1073741824").to_i(10))
    assert_equal(0x4000000000000000, S("4611686018427387904").to_i(10))
    assert_equal(1, S("1__2").to_i(10))
    assert_equal(1, S("1_z").to_i(10))

    bug6192 = '[ruby-core:43566]'
    assert_raise(Encoding::CompatibilityError, bug6192) {S("0".encode("utf-16be")).to_i}
    assert_raise(Encoding::CompatibilityError, bug6192) {S("0".encode("utf-16le")).to_i}
    assert_raise(Encoding::CompatibilityError, bug6192) {S("0".encode("utf-32be")).to_i}
    assert_raise(Encoding::CompatibilityError, bug6192) {S("0".encode("utf-32le")).to_i}
    assert_raise(Encoding::CompatibilityError, bug6192) {S("0".encode("iso-2022-jp")).to_i}
  end

  def test_to_s
    a = S("me")
    assert_equal("me", a.to_s)
    assert_equal(a.__id__, a.to_s.__id__) if @cls == String
  end

  def test_to_str
    a = S("me")
    assert_equal("me", a.to_s)
    assert_equal(a.__id__, a.to_s.__id__) if @cls == String

    o = Object.new
    def o.to_str
      "at"
    end
    assert_equal("meat", a.concat(o))

    o = Object.new
    def o.to_str
      foo_bar()
    end
    assert_match(/foo_bar/, assert_raise(NoMethodError) {a.concat(o)}.message)
  end

  def test_tr
    assert_equal(S("hippo"), S("hello").tr(S("el"), S("ip")))
    assert_equal(S("*e**o"), S("hello").tr(S("^aeiou"), S("*")))
    assert_equal(S("hal"),   S("ibm").tr(S("b-z"), S("a-z")))

    a = S("abc".force_encoding(Encoding::US_ASCII))
    assert_equal(Encoding::US_ASCII, a.tr(S("z"), S("\u0101")).encoding, '[ruby-core:22326]')

    assert_equal("a".hash, S("a").tr("a", "\u0101").tr("\u0101", "a").hash, '[ruby-core:22328]')
    assert_equal(true, S("\u0101").tr("\u0101", "a").ascii_only?)
    assert_equal(true, S("\u3041").tr("\u3041", "a").ascii_only?)
    assert_equal(false, S("\u3041\u3042").tr("\u3041", "a").ascii_only?)

    bug6156 = '[ruby-core:43335]'
    bug13950 = '[ruby-core:83056] [Bug #13950]'
    str, range, star = %w[b a-z *].map{|s|s.encode("utf-16le")}
    result = str.tr(range, star)
    assert_equal(star, result, bug6156)
    assert_not_predicate(str, :ascii_only?)
    assert_not_predicate(star, :ascii_only?)
    assert_not_predicate(result, :ascii_only?, bug13950)
  end

  def test_tr!
    a = S("hello")
    b = a.dup
    assert_equal(S("hippo"), a.tr!(S("el"), S("ip")))
    assert_equal(S("hippo"), a)
    assert_equal(S("hello"),b)

    a = S("hello")
    assert_equal(S("*e**o"), a.tr!(S("^aeiou"), S("*")))
    assert_equal(S("*e**o"), a)

    a = S("IBM")
    assert_equal(S("HAL"), a.tr!(S("B-Z"), S("A-Z")))
    assert_equal(S("HAL"), a)

    a = S("ibm")
    assert_nil(a.tr!(S("B-Z"), S("A-Z")))
    assert_equal(S("ibm"), a)

    a = S("abc".force_encoding(Encoding::US_ASCII))
    assert_nil(a.tr!(S("z"), S("\u0101")), '[ruby-core:22326]')
    assert_equal(Encoding::US_ASCII, a.encoding, '[ruby-core:22326]')
  end

  def test_tr_s
    assert_equal(S("hypo"), S("hello").tr_s(S("el"), S("yp")))
    assert_equal(S("h*o"),  S("hello").tr_s(S("el"), S("*")))
    assert_equal("a".hash, S("\u0101\u0101").tr_s("\u0101", "a").hash)
    assert_equal(true, S("\u3041\u3041").tr("\u3041", "a").ascii_only?)
  end

  def test_tr_s!
    a = S("hello")
    b = a.dup
    assert_equal(S("hypo"),  a.tr_s!(S("el"), S("yp")))
    assert_equal(S("hypo"),  a)
    assert_equal(S("hello"), b)

    a = S("hello")
    assert_equal(S("h*o"), a.tr_s!(S("el"), S("*")))
    assert_equal(S("h*o"), a)
  end

  def test_unpack
    a = [S("cat"),  S("wom"), S("x"), S("yy")]
    assert_equal(a, S("catwomx  yy ").unpack(S("A3A3A3A3")))

    assert_equal([S("cat")], S("cat  \000\000").unpack(S("A*")))
    assert_equal([S("cwx"), S("wx"), S("x"), S("yy")],
                   S("cwx  yy ").unpack(S("A3@1A3@2A3A3")))
    assert_equal([S("cat"), S("wom"), S("x\000\000"), S("yy\000")],
                  S("catwomx\000\000yy\000").unpack(S("a3a3a3a3")))
    assert_equal([S("cat \000\000")], S("cat \000\000").unpack(S("a*")))
    assert_equal([S("ca")], S("catdog").unpack(S("a2")))

    assert_equal([S("cat\000\000")],
                  S("cat\000\000\000\000\000dog").unpack(S("a5")))

    assert_equal([S("01100001")], S("\x61").unpack(S("B8")))
    assert_equal([S("01100001")], S("\x61").unpack(S("B*")))
    assert_equal([S("0110000100110111")], S("\x61\x37").unpack(S("B16")))
    assert_equal([S("01100001"), S("00110111")], S("\x61\x37").unpack(S("B8B8")))
    assert_equal([S("0110")], S("\x60").unpack(S("B4")))

    assert_equal([S("01")], S("\x40").unpack(S("B2")))

    assert_equal([S("01100001")], S("\x86").unpack(S("b8")))
    assert_equal([S("01100001")], S("\x86").unpack(S("b*")))

    assert_equal([S("0110000100110111")], S("\x86\xec").unpack(S("b16")))
    assert_equal([S("01100001"), S("00110111")], S("\x86\xec").unpack(S("b8b8")))

    assert_equal([S("0110")], S("\x06").unpack(S("b4")))
    assert_equal([S("01")], S("\x02").unpack(S("b2")))

    assert_equal([ 65, 66, 67 ],  S("ABC").unpack(S("C3")))
    assert_equal([ 255, 66, 67 ], S("\377BC").unpack("C*"))
    assert_equal([ 65, 66, 67 ],  S("ABC").unpack("c3"))
    assert_equal([ -1, 66, 67 ],  S("\377BC").unpack("c*"))


    assert_equal([S("4142"), S("0a"), S("1")], S("AB\n\x10").unpack(S("H4H2H1")))
    assert_equal([S("1424"), S("a0"), S("2")], S("AB\n\x02").unpack(S("h4h2h1")))

    assert_equal([S("abc\002defcat\001"), S(""), S("")],
                 S("abc=02def=\ncat=\n=01=\n").unpack(S("M9M3M4")))

    assert_equal([S("hello\n")], S("aGVsbG8K\n").unpack(S("m")))

    assert_equal([S("hello\nhello\n")], S(",:&5L;&\\*:&5L;&\\*\n").unpack(S("u")))

    assert_equal([0xa9, 0x42, 0x2260], S("\xc2\xa9B\xe2\x89\xa0").unpack(S("U*")))

=begin
    skipping "Not tested:
        D,d & double-precision float, native format\\
        E & double-precision float, little-endian byte order\\
        e & single-precision float, little-endian byte order\\
        F,f & single-precision float, native format\\
        G & double-precision float, network (big-endian) byte order\\
        g & single-precision float, network (big-endian) byte order\\
        I & unsigned integer\\
        i & integer\\
        L & unsigned long\\
        l & long\\

        m & string encoded in base64 (uuencoded)\\
        N & long, network (big-endian) byte order\\
        n & short, network (big-endian) byte-order\\
        P & pointer to a structure (fixed-length string)\\
        p & pointer to a null-terminated string\\
        S & unsigned short\\
        s & short\\
        V & long, little-endian byte order\\
        v & short, little-endian byte order\\
        X & back up a byte\\
        x & null byte\\
        Z & ASCII string (null padded, count is width)\\
"
=end
  end

  def test_upcase
    assert_equal(S("HELLO"), S("hello").upcase)
    assert_equal(S("HELLO"), S("hello").upcase)
    assert_equal(S("HELLO"), S("HELLO").upcase)
    assert_equal(S("ABC HELLO 123"), S("abc HELLO 123").upcase)
    assert_equal(S("H\0""ELLO"), S("H\0""ello").upcase)
    assert_equal(S("\u{10574}"), S("\u{1059B}").upcase)
  end

  def test_upcase!
    a = S("hello")
    b = a.dup
    assert_equal(S("HELLO"), a.upcase!)
    assert_equal(S("HELLO"), a)
    assert_equal(S("hello"), b)

    a = S("HELLO")
    assert_nil(a.upcase!)
    assert_equal(S("HELLO"), a)

    a = S("H\0""ello")
    b = a.dup
    assert_equal(S("H\0""ELLO"), a.upcase!)
    assert_equal(S("H\0""ELLO"), a)
    assert_equal(S("H\0""ello"), b)
  end

  def test_upto
    a     = S("aa")
    start = S("aa")
    count = 0
    assert_equal(S("aa"), a.upto(S("zz")) {|s|
                   assert_equal(start, s)
                   start.succ!
                   count += 1
                   })
    assert_equal(676, count)
  end

  def test_upto_numeric
    a     = S("00")
    start = S("00")
    count = 0
    assert_equal(S("00"), a.upto(S("23")) {|s|
                   assert_equal(start, s, "[ruby-dev:39361]")
                   assert_equal(Encoding::US_ASCII, s.encoding)
                   start.succ!
                   count += 1
                   })
    assert_equal(24, count, "[ruby-dev:39361]")
  end

  def test_upto_nonalnum
    first = S("\u3041")
    last  = S("\u3093")
    count = 0
    assert_equal(first, first.upto(last) {|s|
                   count += 1
                   s.replace(last)
                   })
    assert_equal(83, count, "[ruby-dev:39626]")
  end

  def test_mod_check
    assert_raise(RuntimeError) {
      s = ""
      s.sub!(/\A/) { s.replace "z" * 2000; "zzz" }
    }
  end

  def test_frozen_check
    assert_raise(FrozenError) {
      s = ""
      s.sub!(/\A/) { s.freeze; "zzz" }
    }
  end

  class S2 < String
  end
  def test_str_new4
    return unless @cls == String

    s = (0..54).to_a.join # length = 100
    s2 = S2.new(s[10,90])
    s3 = s2[10,80]
    assert_equal((10..54).to_a.to_a.join, s2)
    assert_equal((15..54).to_a.to_a.join, s3)
  end

  def test_rb_str_new4
    s = S("a" * 100)
    s2 = s[10,90]
    assert_equal("a" * 90, s2)
    s3 = s2[10,80]
    assert_equal("a" * 80, s3)
  end

  class StringLike
    def initialize(str)
      @str = str
    end

    def to_str
      @str
    end
  end

  def test_rb_str_to_str
    assert_equal("ab", S("a") + StringLike.new("b"))
  end

  def test_rb_str_shared_replace
    s = S("a" * 100)
    s.succ!
    assert_equal("a" * 99 + "b", s)
    s = ""
    s.succ!
    assert_equal("", s)
  end

  def test_times
    assert_raise(ArgumentError) { "a" * (-1) }
  end

  def test_splice!
    l = S("1234\n234\n34\n4\n")
    assert_equal(S("1234\n"), l.slice!(/\A.*\n/), "[ruby-dev:31665]")
    assert_equal(S("234\n"), l.slice!(/\A.*\n/), "[ruby-dev:31665]")
    assert_equal(S("34\n"), l.slice!(/\A.*\n/), "[ruby-dev:31665]")
    assert_equal(S("4\n"), l.slice!(/\A.*\n/), "[ruby-dev:31665]")
    assert_nil(l.slice!(/\A.*\n/), "[ruby-dev:31665]")
  end

  def test_times2
    s1 = ''
    100.times {|n|
      s2 = S("a") * n
      assert_equal(s1, s2)
      s1 << 'a'
    }

    assert_raise(ArgumentError) { S("foo") * (-1) }
  end

  def test_respond_to
    o = Object.new
    def o.respond_to?(arg) [:to_str].include?(arg) ? nil : super end
    def o.to_str() "" end
    def o.==(other) "" == other end
    assert_equal(false, S("") == o)
  end

  def test_match_method
    assert_equal("bar", S("foobarbaz").match(/bar/).to_s)

    o = Regexp.new('foo')
    def o.match(x, y, z); x + y + z; end
    assert_equal("foobarbaz", S("foo").match(o, "bar", "baz"))
    x = nil
    S("foo").match(o, "bar", "baz") {|y| x = y }
    assert_equal("foobarbaz", x)

    assert_raise(ArgumentError) { S("foo").match }
  end

  def test_match_p_regexp
    /backref/ =~ 'backref'
    # must match here, but not in a separate method, e.g., assert_send,
    # to check if $~ is affected or not.
    assert_equal(true, S("").match?(//))
    assert_equal(true, :abc.match?(/.../))
    assert_equal(true, S('abc').match?(/b/))
    assert_equal(true, S('abc').match?(/b/, 1))
    assert_equal(true, S('abc').match?(/../, 1))
    assert_equal(true, S('abc').match?(/../, -2))
    assert_equal(false, S('abc').match?(/../, -4))
    assert_equal(false, S('abc').match?(/../, 4))
    assert_equal(true, S("\u3042xx").match?(/../, 1))
    assert_equal(false, S("\u3042x").match?(/../, 1))
    assert_equal(true, S('').match?(/\z/))
    assert_equal(true, S('abc').match?(/\z/))
    assert_equal(true, S('Ruby').match?(/R.../))
    assert_equal(false, S('Ruby').match?(/R.../, 1))
    assert_equal(false, S('Ruby').match?(/P.../))
    assert_equal('backref', $&)
  end

  def test_match_p_string
    /backref/ =~ 'backref'
    # must match here, but not in a separate method, e.g., assert_send,
    # to check if $~ is affected or not.
    assert_equal(true, S("").match?(''))
    assert_equal(true, :abc.match?('...'))
    assert_equal(true, S('abc').match?('b'))
    assert_equal(true, S('abc').match?('b', 1))
    assert_equal(true, S('abc').match?('..', 1))
    assert_equal(true, S('abc').match?('..', -2))
    assert_equal(false, S('abc').match?('..', -4))
    assert_equal(false, S('abc').match?('..', 4))
    assert_equal(true, S("\u3042xx").match?('..', 1))
    assert_equal(false, S("\u3042x").match?('..', 1))
    assert_equal(true, S('').match?('\z'))
    assert_equal(true, S('abc').match?('\z'))
    assert_equal(true, S('Ruby').match?('R...'))
    assert_equal(false, S('Ruby').match?('R...', 1))
    assert_equal(false, S('Ruby').match?('P...'))
    assert_equal('backref', $&)
  end

  def test_clear
    s = "foo" * 100
    s.clear
    assert_equal("", s)
  end

  def test_to_s_2
    c = Class.new(String)
    s = c.new
    s.replace("foo")
    assert_equal("foo", s.to_s)
    assert_instance_of(String, s.to_s)
  end

  def test_inspect_nul
    bug8290 = '[ruby-core:54458]'
    s = S("\0") + "12"
    assert_equal '"\u000012"', s.inspect, bug8290
    s = S("\0".b) + "12"
    assert_equal '"\x0012"', s.inspect, bug8290
  end

  def test_inspect_next_line
    bug16842 = '[ruby-core:98231]'
    assert_equal '"\\u0085"', 0x85.chr(Encoding::UTF_8).inspect, bug16842
  end

  def test_partition
    assert_equal(%w(he l lo), S("hello").partition(/l/))
    assert_equal(%w(he l lo), S("hello").partition("l"))
    assert_raise(TypeError) { S("hello").partition(1) }
    def (hyphen = Object.new).to_str; "-"; end
    assert_equal(%w(foo - bar), S("foo-bar").partition(hyphen), '[ruby-core:23540]')

    bug6206 = '[ruby-dev:45441]'
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      s = S("a:".force_encoding(enc))
      assert_equal([enc]*3, s.partition("|").map(&:encoding), bug6206)
    end

    assert_equal(["\u30E6\u30FC\u30B6", "@", "\u30C9\u30E1.\u30A4\u30F3"],
                 S("\u30E6\u30FC\u30B6@\u30C9\u30E1.\u30A4\u30F3").partition(/[@.]/))

    bug = '[ruby-core:82911]'
    hello = S("hello")
    hello.partition("hi").map(&:upcase!)
    assert_equal("hello", hello, bug)

    assert_equal(["", "", "foo"], S("foo").partition(/^=*/))

    assert_equal([S("ab"), S("c"), S("dbce")], S("abcdbce").partition(/b\Kc/))
  end

  def test_rpartition
    assert_equal(%w(hel l o), S("hello").rpartition(/l/))
    assert_equal(%w(hel l o), S("hello").rpartition("l"))
    assert_raise(TypeError) { S("hello").rpartition(1) }
    def (hyphen = Object.new).to_str; "-"; end
    assert_equal(%w(foo - bar), S("foo-bar").rpartition(hyphen), '[ruby-core:23540]')

    bug6206 = '[ruby-dev:45441]'
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      s = S("a:".force_encoding(enc))
      assert_equal([enc]*3, s.rpartition("|").map(&:encoding), bug6206)
    end

    bug8138 = '[ruby-dev:47183]'
    assert_equal(["\u30E6\u30FC\u30B6@\u30C9\u30E1", ".", "\u30A4\u30F3"],
      S("\u30E6\u30FC\u30B6@\u30C9\u30E1.\u30A4\u30F3").rpartition(/[@.]/), bug8138)

    bug = '[ruby-core:82911]'
    hello = "hello"
    hello.rpartition("hi").map(&:upcase!)
    assert_equal("hello", hello, bug)

    assert_equal([S("abcdb"), S("c"), S("e")], S("abcdbce").rpartition(/b\Kc/))
  end

  def test_fs_setter
    return unless @cls == String

    assert_raise(TypeError) { $/ = 1 }
    name = "\u{5206 884c}"
    assert_separately([], "#{<<~"do;"}\n#{<<~"end;"}")
    do;
      alias $#{name} $/
      assert_raise_with_message(TypeError, /\\$#{name}/) { $#{name} = 1 }
    end;
  end

  def test_to_id
    c = Class.new
    c.class_eval do
      def initialize
        @foo = :foo
      end
    end

    assert_raise(TypeError) do
      c.class_eval { attr 1 }
    end

    o = Object.new
    def o.to_str; :foo; end
    assert_raise(TypeError) do
      c.class_eval { attr 1 }
    end

    class << o;remove_method :to_str;end
    def o.to_str; "foo"; end
    assert_nothing_raised do
      c.class_eval { attr o }
    end
    assert_equal(:foo, c.new.foo)
  end

  def test_gsub_enumerator
    e = S("abc").gsub(/./)
    assert_equal("a", e.next, "[ruby-dev:34828]")
    assert_equal("b", e.next)
    assert_equal("c", e.next)
  end

  def test_clear_nonasciicompat
    assert_equal("", S("\u3042".encode("ISO-2022-JP")).clear)
  end

  def test_try_convert
    assert_equal(nil, @cls.try_convert(1))
    assert_equal("foo", @cls.try_convert("foo"))
  end

  def test_substr_negative_begin
    assert_equal("\u3042", ("\u3042" * 100)[-1])
  end

=begin
  def test_compare_different_encoding_string
    s1 = S("\xff".force_encoding("UTF-8"))
    s2 = S("\xff".force_encoding("ISO-2022-JP"))
    assert_equal([-1, 1], [s1 <=> s2, s2 <=> s1].sort)
  end
=end

  def test_casecmp
    assert_equal(0, S("FoO").casecmp("fOO"))
    assert_equal(1, S("FoO").casecmp("BaR"))
    assert_equal(-1, S("baR").casecmp("FoO"))
    assert_equal(1, S("\u3042B").casecmp("\u3042a"))
    assert_equal(-1, S("foo").casecmp("foo\0"))

    assert_nil(S("foo").casecmp(:foo))
    assert_nil(S("foo").casecmp(Object.new))

    o = Object.new
    def o.to_str; "fOO"; end
    assert_equal(0, S("FoO").casecmp(o))
  end

  def test_casecmp?
    assert_equal(true, S('FoO').casecmp?('fOO'))
    assert_equal(false, S('FoO').casecmp?('BaR'))
    assert_equal(false, S('baR').casecmp?('FoO'))
    assert_equal(true, S('äöü').casecmp?('ÄÖÜ'))
    assert_equal(false, S("foo").casecmp?("foo\0"))

    assert_nil(S("foo").casecmp?(:foo))
    assert_nil(S("foo").casecmp?(Object.new))

    o = Object.new
    def o.to_str; "fOO"; end
    assert_equal(true, S("FoO").casecmp?(o))
  end

  def test_upcase2
    assert_equal("\u3042AB", S("\u3042aB").upcase)
  end

  def test_downcase2
    assert_equal("\u3042ab", S("\u3042aB").downcase)
  end

  def test_rstrip
    assert_equal("  hello", S("  hello  ").rstrip)
    assert_equal("\u3042", S("\u3042   ").rstrip)
    assert_equal("\u3042", S("\u3042\u0000").rstrip)
    assert_raise(Encoding::CompatibilityError) { S("\u3042".encode("ISO-2022-JP")).rstrip }
  end

  def test_rstrip_bang
    s1 = S("  hello  ")
    assert_equal("  hello", s1.rstrip!)
    assert_equal("  hello", s1)

    s2 = S("\u3042  ")
    assert_equal("\u3042", s2.rstrip!)
    assert_equal("\u3042", s2)

    s3 = S("  \u3042")
    assert_equal(nil, s3.rstrip!)
    assert_equal("  \u3042", s3)

    s4 = S("\u3042")
    assert_equal(nil, s4.rstrip!)
    assert_equal("\u3042", s4)

    s5 = S("\u3042\u0000")
    assert_equal("\u3042", s5.rstrip!)
    assert_equal("\u3042", s5)

    assert_raise(Encoding::CompatibilityError) { S("\u3042".encode("ISO-2022-JP")).rstrip! }
    assert_raise(Encoding::CompatibilityError) { S("abc \x80 ".force_encoding('UTF-8')).rstrip! }
    assert_raise(Encoding::CompatibilityError) { S("abc\x80 ".force_encoding('UTF-8')).rstrip! }
    assert_raise(Encoding::CompatibilityError) { S("abc \x80".force_encoding('UTF-8')).rstrip! }
    assert_raise(Encoding::CompatibilityError) { S("\x80".force_encoding('UTF-8')).rstrip! }
    assert_raise(Encoding::CompatibilityError) { S(" \x80 ".force_encoding('UTF-8')).rstrip! }
  end

  def test_lstrip
    assert_equal("hello  ", S("  hello  ").lstrip)
    assert_equal("\u3042", S("   \u3042").lstrip)
    assert_equal("hello  ", S("\x00hello  ").lstrip)
  end

  def test_lstrip_bang
    s1 = S("  hello  ")
    assert_equal("hello  ", s1.lstrip!)
    assert_equal("hello  ", s1)

    s2 = S("\u3042  ")
    assert_equal(nil, s2.lstrip!)
    assert_equal("\u3042  ", s2)

    s3 = S("  \u3042")
    assert_equal("\u3042", s3.lstrip!)
    assert_equal("\u3042", s3)

    s4 = S("\u3042")
    assert_equal(nil, s4.lstrip!)
    assert_equal("\u3042", s4)

    s5 = S("\u0000\u3042")
    assert_equal("\u3042", s5.lstrip!)
    assert_equal("\u3042", s5)

  end

  def test_delete_prefix
    assert_raise(TypeError) { S('hello').delete_prefix(nil) }
    assert_raise(TypeError) { S('hello').delete_prefix(1) }
    assert_raise(TypeError) { S('hello').delete_prefix(/hel/) }

    s = S("hello")
    assert_equal("lo", s.delete_prefix('hel'))
    assert_equal("hello", s)

    s = S("hello")
    assert_equal("hello", s.delete_prefix('lo'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{306b 3061 306f}", s.delete_prefix("\u{3053 3093}"))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b 3061 306f}", s.delete_prefix('hel'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal("hello", s.delete_prefix("\u{3053 3093}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal("\xe3\x81\x82", s.delete_prefix("\xe3"))
    assert_equal("\xe3\x81\x82", s)

    s = S("\x95\x5c").force_encoding("Shift_JIS")
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s.delete_prefix("\x95"))
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s)

    # clear coderange
    s = S("\u{3053 3093}hello")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.delete_prefix("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("bba", s.delete_prefix(klass.new))
    assert_equal("abba", s)
  end

  def test_delete_prefix_bang
    assert_raise(TypeError) { S('hello').delete_prefix!(nil) }
    assert_raise(TypeError) { S('hello').delete_prefix!(1) }
    assert_raise(TypeError) { S('hello').delete_prefix!(/hel/) }

    s = S("hello")
    assert_equal("lo", s.delete_prefix!('hel'))
    assert_equal("lo", s)

    s = S("hello")
    assert_equal(nil, s.delete_prefix!('lo'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{306b 3061 306f}", s.delete_prefix!("\u{3053 3093}"))
    assert_equal("\u{306b 3061 306f}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal(nil, s.delete_prefix!('hel'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal(nil, s.delete_prefix!("\u{3053 3093}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal(nil, s.delete_prefix!("\xe3"))
    assert_equal("\xe3\x81\x82", s)

    # clear coderange
    s = S("\u{3053 3093}hello")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.delete_prefix!("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("bba", s.delete_prefix!(klass.new))
    assert_equal("bba", s)

    s = S("ax").freeze
    assert_raise_with_message(FrozenError, /frozen/) {s.delete_prefix!("a")}

    s = S("ax")
    o = Struct.new(:s).new(s)
    def o.to_str
      s.freeze
      "a"
    end
    assert_raise_with_message(FrozenError, /frozen/) {s.delete_prefix!(o)}
  end

  def test_delete_suffix
    assert_raise(TypeError) { S('hello').delete_suffix(nil) }
    assert_raise(TypeError) { S('hello').delete_suffix(1) }
    assert_raise(TypeError) { S('hello').delete_suffix(/hel/) }

    s = S("hello")
    assert_equal("hel", s.delete_suffix('lo'))
    assert_equal("hello", s)

    s = S("hello")
    assert_equal("hello", s.delete_suffix('he'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b}", s.delete_suffix("\u{3061 306f}"))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b 3061 306f}", s.delete_suffix('lo'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal("hello", s.delete_suffix("\u{3061 306f}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal("\xe3\x81\x82", s.delete_suffix("\x82"))
    assert_equal("\xe3\x81\x82", s)

    # clear coderange
    s = S("hello\u{3053 3093}")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.delete_suffix("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("abb", s.delete_suffix(klass.new))
    assert_equal("abba", s)

    # chomp removes any of "\n", "\r\n", "\r" when "\n" is specified,
    # but delete_suffix does not
    s = "foo\n"
    assert_equal("foo", s.delete_suffix("\n"))
    s = "foo\r\n"
    assert_equal("foo\r", s.delete_suffix("\n"))
    s = "foo\r"
    assert_equal("foo\r", s.delete_suffix("\n"))
  end

  def test_delete_suffix_bang
    assert_raise(TypeError) { S('hello').delete_suffix!(nil) }
    assert_raise(TypeError) { S('hello').delete_suffix!(1) }
    assert_raise(TypeError) { S('hello').delete_suffix!(/hel/) }

    s = S("hello").freeze
    assert_raise_with_message(FrozenError, /frozen/) {s.delete_suffix!('lo')}

    s = S("ax")
    o = Struct.new(:s).new(s)
    def o.to_str
      s.freeze
      "x"
    end
    assert_raise_with_message(FrozenError, /frozen/) {s.delete_suffix!(o)}

    s = S("hello")
    assert_equal("hel", s.delete_suffix!('lo'))
    assert_equal("hel", s)

    s = S("hello")
    assert_equal(nil, s.delete_suffix!('he'))
    assert_equal("hello", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal("\u{3053 3093 306b}", s.delete_suffix!("\u{3061 306f}"))
    assert_equal("\u{3053 3093 306b}", s)

    s = S("\u{3053 3093 306b 3061 306f}")
    assert_equal(nil, s.delete_suffix!('lo'))
    assert_equal("\u{3053 3093 306b 3061 306f}", s)

    s = S("hello")
    assert_equal(nil, s.delete_suffix!("\u{3061 306f}"))
    assert_equal("hello", s)

    # skip if argument is a broken string
    s = S("\xe3\x81\x82")
    assert_equal(nil, s.delete_suffix!("\x82"))
    assert_equal("\xe3\x81\x82", s)

    s = S("\x95\x5c").force_encoding("Shift_JIS")
    assert_equal(nil, s.delete_suffix!("\x5c"))
    assert_equal("\x95\x5c".force_encoding("Shift_JIS"), s)

    # clear coderange
    s = S("hello\u{3053 3093}")
    assert_not_predicate(s, :ascii_only?)
    assert_predicate(s.delete_suffix!("\u{3053 3093}"), :ascii_only?)

    # argument should be converted to String
    klass = Class.new { def to_str; 'a'; end }
    s = S("abba")
    assert_equal("abb", s.delete_suffix!(klass.new))
    assert_equal("abb", s)

    # chomp removes any of "\n", "\r\n", "\r" when "\n" is specified,
    # but delete_suffix does not
    s = "foo\n"
    assert_equal("foo", s.delete_suffix!("\n"))
    s = "foo\r\n"
    assert_equal("foo\r", s.delete_suffix!("\n"))
    s = "foo\r"
    assert_equal(nil, s.delete_suffix!("\n"))
  end

=begin
  def test_symbol_table_overflow
    assert_in_out_err([], <<-INPUT, [], /symbol table overflow \(symbol [a-z]{8}\) \(RuntimeError\)/)
      ("aaaaaaaa".."zzzzzzzz").each {|s| s.to_sym }
    INPUT
  end
=end

  def test_nesting_shared
    a = ('a' * 24).encode(Encoding::ASCII).gsub('x', '')
    hash = {}
    hash[a] = true
    assert_equal(('a' * 24), a)
    4.times { GC.start }
    assert_equal(('a' * 24), a, '[Bug #15792]')
  end

  def test_nesting_shared_b
    a = ('j' * 24).b.b
    eval('', binding, a)
    assert_equal(('j' * 24), a)
    4.times { GC.start }
    assert_equal(('j' * 24), a, '[Bug #15934]')
  end

  def test_shared_force_encoding
    s = S("\u{3066}\u{3059}\u{3068}").gsub(//, '')
    h = {}
    h[s] = nil
    k = h.keys[0]
    assert_equal(s, k, '[ruby-dev:39068]')
    assert_equal(Encoding::UTF_8, k.encoding, '[ruby-dev:39068]')
    s.dup.force_encoding(Encoding::ASCII_8BIT).gsub(//, '')
    k = h.keys[0]
    assert_equal(s, k, '[ruby-dev:39068]')
    assert_equal(Encoding::UTF_8, k.encoding, '[ruby-dev:39068]')
  end

  def test_ascii_incomat_inspect
    bug4081 = '[ruby-core:33283]'
    WIDE_ENCODINGS.each do |e|
      assert_equal('"abc"', S("abc".encode(e)).inspect)
      assert_equal('"\\u3042\\u3044\\u3046"', S("\u3042\u3044\u3046".encode(e)).inspect)
      assert_equal('"ab\\"c"', S("ab\"c".encode(e)).inspect, bug4081)
    end
    begin
      verbose, $VERBOSE = $VERBOSE, nil
      ext = Encoding.default_external
      Encoding.default_external = "us-ascii"
      $VERBOSE = verbose
      i = S("abc\"\\".force_encoding("utf-8")).inspect
    ensure
      $VERBOSE = nil
      Encoding.default_external = ext
      $VERBOSE = verbose
    end
    assert_equal('"abc\\"\\\\"', i, bug4081)
  end

  def test_dummy_inspect
    assert_equal('"\e\x24\x42\x22\x4C\x22\x68\e\x28\x42"',
                 S("\u{ffe2}\u{2235}".encode("cp50220")).inspect)
  end

  def test_prepend
    assert_equal(S("hello world!"), S("!").prepend("hello ", "world"))
    b = S("ue")
    assert_equal(S("ueueue"), b.prepend(b, b))

    foo = Object.new
    def foo.to_str
      "b"
    end
    assert_equal(S("ba"), S("a").prepend(foo))

    a = S("world")
    b = S("hello ")
    a.prepend(b)
    assert_equal(S("hello world"), a)
    assert_equal(S("hello "), b)
  end

  def u(str)
    str.force_encoding(Encoding::UTF_8)
  end

  def test_byteslice
    assert_equal("h", S("hello").byteslice(0))
    assert_equal(nil, S("hello").byteslice(5))
    assert_equal("o", S("hello").byteslice(-1))
    assert_equal(nil, S("hello").byteslice(-6))

    assert_equal("", S("hello").byteslice(0, 0))
    assert_equal("hello", S("hello").byteslice(0, 6))
    assert_equal("hello", S("hello").byteslice(0, 6))
    assert_equal("", S("hello").byteslice(5, 1))
    assert_equal("o", S("hello").byteslice(-1, 6))
    assert_equal(nil, S("hello").byteslice(-6, 1))
    assert_equal(nil, S("hello").byteslice(0, -1))

    assert_equal("h", S("hello").byteslice(0..0))
    assert_equal("", S("hello").byteslice(5..0))
    assert_equal("o", S("hello").byteslice(4..5))
    assert_equal(nil, S("hello").byteslice(6..0))
    assert_equal("", S("hello").byteslice(-1..0))
    assert_equal("llo", S("hello").byteslice(-3..5))

    assert_equal(u("\x81"), S("\u3042").byteslice(1))
    assert_equal(u("\x81\x82"), S("\u3042").byteslice(1, 2))
    assert_equal(u("\x81\x82"), S("\u3042").byteslice(1..2))

    assert_equal(u("\x82")+("\u3042"*9), S("\u3042"*10).byteslice(2, 28))

    bug7954 = '[ruby-dev:47108]'
    assert_equal(false, S("\u3042").byteslice(0, 2).valid_encoding?, bug7954)
    assert_equal(false, ("\u3042"*10).byteslice(0, 20).valid_encoding?, bug7954)
  end

  def test_unknown_string_option
    str = nil
    assert_nothing_raised(SyntaxError) do
      eval(%{
        str = begin"hello"end
      })
    end
    assert_equal "hello", str
  end

  def test_eq_tilde_can_be_overridden
    return unless @cls == String

    assert_separately([], <<-RUBY)
      class String
        undef =~
        def =~(str)
          "foo"
        end
      end

      assert_equal("foo", "" =~ //)
    RUBY
  end

  class Bug9581 < String
    def =~ re; :foo end
  end

  def test_regexp_match_subclass
    s = Bug9581.new(S("abc"))
    r = /abc/
    assert_equal(:foo, s =~ r)
    assert_equal(:foo, s.send(:=~, r))
    assert_equal(:foo, s.send(:=~, /abc/))
    assert_equal(:foo, s =~ /abc/, "should not use optimized instruction")
  end

  def test_LSHIFT_neary_long_max
    return unless @cls == String

    assert_ruby_status([], <<-'end;', '[ruby-core:61886] [Bug #9709]', timeout: 20)
      begin
        a = "a" * 0x4000_0000
        a << "a" * 0x1_0000
      rescue NoMemoryError
      end
    end;
  end if [0].pack("l!").bytesize < [nil].pack("p").bytesize
  # enable only when string size range is smaller than memory space

  def test_uplus_minus
    return unless @cls == String

    str = "foo"
    assert_not_predicate(str, :frozen?)
    assert_not_predicate(+str, :frozen?)
    assert_predicate(-str, :frozen?)

    assert_same(str, +str)
    assert_not_same(str, -str)

    str = "bar".freeze
    assert_predicate(str, :frozen?)
    assert_not_predicate(+str, :frozen?)
    assert_predicate(-str, :frozen?)

    assert_not_same(str, +str)
    assert_same(str, -str)

    bar = %w(b a r).join('')
    assert_same(str, -bar, "uminus deduplicates [Feature #13077]")
  end

  def test_uminus_frozen
    return unless @cls == String

    # embedded
    str1 = ("foobar" * 3).freeze
    str2 = ("foobar" * 3).freeze
    assert_not_same str1, str2
    assert_same str1, -str1
    assert_same str1, -str2

    # regular
    str1 = ("foobar" * 4).freeze
    str2 = ("foobar" * 4).freeze
    assert_not_same str1, str2
    assert_same str1, -str1
    assert_same str1, -str2
  end

  def test_uminus_no_freeze_not_bare
    str = S("foo")
    assert_instance_of(@cls, -str)
    assert_equal(false, str.frozen?)

    str = S("foo")
    str.instance_variable_set(:@iv, 1)
    assert_instance_of(@cls, -str)
    assert_equal(false, str.frozen?)
    assert_equal(1, str.instance_variable_get(:@iv))

    str = S("foo")
    assert_instance_of(@cls, -str)
    assert_equal(false, str.frozen?)
  end

  def test_ord
    assert_equal(97, S("a").ord)
    assert_equal(97, S("abc").ord)
    assert_equal(0x3042, S("\u3042\u3043").ord)
    assert_raise(ArgumentError) { S("").ord }
  end

  def test_chr
    assert_equal("a", S("abcde").chr)
    assert_equal("a", S("a").chr)
    assert_equal("\u3042", S("\u3042\u3043").chr)
    assert_equal('', S('').chr)
  end

  def test_substr_code_range
    data = S("\xff" + "a"*200)
    assert_not_predicate(data, :valid_encoding?)
    assert_predicate(data[100..-1], :valid_encoding?)
  end

  def test_byteindex
    assert_equal(0, S("hello").byteindex(?h))
    assert_equal(1, S("hello").byteindex(S("ell")))
    assert_equal(2, S("hello").byteindex(/ll./))

    assert_equal(3, S("hello").byteindex(?l, 3))
    assert_equal(3, S("hello").byteindex(S("l"), 3))
    assert_equal(3, S("hello").byteindex(/l./, 3))

    assert_nil(S("hello").byteindex(?z, 3))
    assert_nil(S("hello").byteindex(S("z"), 3))
    assert_nil(S("hello").byteindex(/z./, 3))

    assert_nil(S("hello").byteindex(?z))
    assert_nil(S("hello").byteindex(S("z")))
    assert_nil(S("hello").byteindex(/z./))

    assert_equal(0, S("").byteindex(S("")))
    assert_equal(0, S("").byteindex(//))
    assert_nil(S("").byteindex(S("hello")))
    assert_nil(S("").byteindex(/hello/))
    assert_equal(0, S("hello").byteindex(S("")))
    assert_equal(0, S("hello").byteindex(//))

    s = S("long") * 1000 << "x"
    assert_nil(s.byteindex(S("y")))
    assert_equal(4 * 1000, s.byteindex(S("x")))
    s << "yx"
    assert_equal(4 * 1000, s.byteindex(S("x")))
    assert_equal(4 * 1000, s.byteindex(S("xyx")))

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal(3, S("foobarbarbaz").byteindex(o))
    assert_raise(TypeError) { S("foo").byteindex(Object.new) }

    assert_nil(S("foo").byteindex(//, -100))
    assert_nil($~)

    assert_equal(2, S("abcdbce").byteindex(/b\Kc/))

    assert_equal(0, S("こんにちは").byteindex(?こ))
    assert_equal(3, S("こんにちは").byteindex(S("んにち")))
    assert_equal(6, S("こんにちは").byteindex(/にち./))

    assert_equal(0, S("にんにちは").byteindex(?に, 0))
    assert_raise(IndexError) { S("にんにちは").byteindex(?に, 1) }
    assert_raise(IndexError) { S("にんにちは").byteindex(?に, 5) }
    assert_equal(6, S("にんにちは").byteindex(?に, 6))
    assert_equal(6, S("にんにちは").byteindex(S("に"), 6))
    assert_equal(6, S("にんにちは").byteindex(/に./, 6))
    assert_raise(IndexError) { S("にんにちは").byteindex(?に, 7) }

    s = S("foobarbarbaz")
    assert !1000.times.any? {s.byteindex("", 100_000_000)}
  end

  def test_byterindex
    assert_equal(3, S("hello").byterindex(?l))
    assert_equal(6, S("ell, hello").byterindex(S("ell")))
    assert_equal(7, S("ell, hello").byterindex(/ll./))

    assert_equal(3, S("hello,lo").byterindex(?l, 3))
    assert_equal(3, S("hello,lo").byterindex(S("l"), 3))
    assert_equal(3, S("hello,lo").byterindex(/l./, 3))

    assert_nil(S("hello").byterindex(?z,     3))
    assert_nil(S("hello").byterindex(S("z"), 3))
    assert_nil(S("hello").byterindex(/z./,   3))

    assert_nil(S("hello").byterindex(?z))
    assert_nil(S("hello").byterindex(S("z")))
    assert_nil(S("hello").byterindex(/z./))

    assert_equal(5, S("hello").byterindex(S("")))
    assert_equal(5, S("hello").byterindex(S(""), 5))
    assert_equal(4, S("hello").byterindex(S(""), 4))
    assert_equal(0, S("hello").byterindex(S(""), 0))

    o = Object.new
    def o.to_str; "bar"; end
    assert_equal(6, S("foobarbarbaz").byterindex(o))
    assert_raise(TypeError) { S("foo").byterindex(Object.new) }

    assert_nil(S("foo").byterindex(//, -100))
    assert_nil($~)

    assert_equal(3, S("foo").byterindex(//))
    assert_equal([3, 3], $~.offset(0))

    assert_equal(5, S("abcdbce").byterindex(/b\Kc/))

    assert_equal(6, S("こんにちは").byterindex(?に))
    assert_equal(18, S("にちは、こんにちは").byterindex(S("にちは")))
    assert_equal(18, S("にちは、こんにちは").byterindex(/にち./))

    assert_raise(IndexError) { S("にちは、こんにちは").byterindex(S("にちは"), 19) }
    assert_raise(IndexError) { S("にちは、こんにちは").byterindex(S("にちは"), -2) }
    assert_equal(18, S("にちは、こんにちは").byterindex(S("にちは"), 18))
    assert_equal(18, S("にちは、こんにちは").byterindex(S("にちは"), -3))
    assert_raise(IndexError) { S("にちは、こんにちは").byterindex(S("にちは"), 17) }
    assert_raise(IndexError) { S("にちは、こんにちは").byterindex(S("にちは"), -4) }
    assert_raise(IndexError) { S("にちは、こんにちは").byterindex(S("にちは"), 1) }
    assert_equal(0, S("にちは、こんにちは").byterindex(S("にちは"), 0))

    assert_equal(0, S("こんにちは").byterindex(S("こんにちは")))
    assert_nil(S("こんにち").byterindex(S("こんにちは")))
    assert_nil(S("こ").byterindex(S("こんにちは")))
    assert_nil(S("").byterindex(S("こんにちは")))
  end

  def test_bytesplice
    assert_bytesplice_raise(IndexError, S("hello"), -6, 0, "xxx")
    assert_bytesplice_result("xxxhello", S("hello"), -5, 0, "xxx")
    assert_bytesplice_result("xxxhello", S("hello"), 0, 0, "xxx")
    assert_bytesplice_result("xxxello", S("hello"), 0, 1, "xxx")
    assert_bytesplice_result("xxx", S("hello"), 0, 5, "xxx")
    assert_bytesplice_result("xxx", S("hello"), 0, 6, "xxx")

    assert_bytesplice_raise(RangeError, S("hello"), -6...-6, "xxx")
    assert_bytesplice_result("xxxhello", S("hello"), -5...-5, "xxx")
    assert_bytesplice_result("xxxhello", S("hello"), 0...0, "xxx")
    assert_bytesplice_result("xxxello", S("hello"), 0..0, "xxx")
    assert_bytesplice_result("xxxello", S("hello"), 0...1, "xxx")
    assert_bytesplice_result("xxxllo", S("hello"), 0..1, "xxx")
    assert_bytesplice_result("xxx", S("hello"), 0..-1, "xxx")
    assert_bytesplice_result("xxx", S("hello"), 0...5, "xxx")
    assert_bytesplice_result("xxx", S("hello"), 0...6, "xxx")

    assert_bytesplice_raise(TypeError, S("hello"), 0, "xxx")

    assert_bytesplice_raise(IndexError, S("こんにちは"), -16, 0, "xxx")
    assert_bytesplice_result("xxxこんにちは", S("こんにちは"), -15, 0, "xxx")
    assert_bytesplice_result("xxxこんにちは", S("こんにちは"), 0, 0, "xxx")
    assert_bytesplice_raise(IndexError, S("こんにちは"), 1, 0, "xxx")
    assert_bytesplice_raise(IndexError, S("こんにちは"), 0, 1, "xxx")
    assert_bytesplice_raise(IndexError, S("こんにちは"), 0, 2, "xxx")
    assert_bytesplice_result("xxxんにちは", S("こんにちは"), 0, 3, "xxx")
    assert_bytesplice_result("こんにちはxxx", S("こんにちは"), 15, 0, "xxx")

    assert_bytesplice_result("", S(""), 0, 0, "")
    assert_bytesplice_result("xxx", S(""), 0, 0, "xxx")
  end

  private

  def assert_bytesplice_result(expected, s, *args)
    assert_equal(expected, s.send(:bytesplice, *args))
    assert_equal(expected, s)
  end

  def assert_bytesplice_raise(e, s, *args)
    assert_raise(e) { s.send(:bytesplice, *args) }
  end
end

class TestString2 < TestString
  def initialize(*args)
    super
    @cls = S2
  end
end
