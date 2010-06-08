require 'test/unit'

class TestRegexp < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_ruby_core_27247
    assert_match(/(a){2}z/, "aaz")
  end

  def test_ruby_dev_24643
    assert_nothing_raised("[ruby-dev:24643]") {
      /(?:(?:[a]*[a])?b)*a*$/ =~ "aabaaca"
    }
  end

  def test_ruby_talk_116455
    assert_match(/^(\w{2,}).* ([A-Za-z\xa2\xc0-\xff]{2,}?)$/n, "Hallo Welt")
  end

  def test_ruby_dev_24887
    assert_equal("a".gsub(/a\Z/, ""), "")
  end

  def test_yoshidam_net_20041111_1
    s = "[\xC2\xA0-\xC3\xBE]"
    assert_match(Regexp.new(s, nil, "u"), "\xC3\xBE")
  end

  def test_ruby_dev_31309
    assert_equal('Ruby', 'Ruby'.sub(/[^a-z]/i, '-'))
  end

  def test_assert_normal_exit
    # moved from knownbug.  It caused core.
    Regexp.union("a", "a")
  end

  def test_to_s
    assert_equal '(?-mix:\000)', Regexp.new("\0").to_s
  end

  def test_source
    assert_equal('', //.source)
  end

  def test_inspect
    assert_equal('//', //.inspect)
    assert_equal('//i', //i.inspect)
    assert_equal('/\//i', /\//i.inspect)
    assert_equal('/\//i', %r"#{'/'}"i.inspect)
    assert_equal('/\/x/i', /\/x/i.inspect)
    assert_equal('/\000/i', /#{"\0"}/i.inspect)
    assert_equal("/\n/i", /#{"\n"}/i.inspect)
    s = [0xff].pack("C")
    assert_equal('/\/'+s.dump.delete('"')+'/i', /\/#{s}/i.inspect)
  end

  def test_char_to_option
    assert_equal("BAR", "FOOBARBAZ"[/b../i])
    assert_equal("bar", "foobarbaz"[/  b  .  .  /x])
    assert_equal("bar\n", "foo\nbar\nbaz"[/b.../m])
    assert_raise(SyntaxError) { eval('//z') }
  end

  def test_char_to_option_kcode
    assert_equal("bar", "foobarbaz"[/b../s])
    assert_equal("bar", "foobarbaz"[/b../e])
    assert_equal("bar", "foobarbaz"[/b../u])
  end

  def test_to_s2
    assert_equal('(?-mix:foo)', /(?:foo)/.to_s)
    assert_equal('(?m-ix:foo)', /(?:foo)/m.to_s)
    assert_equal('(?mi-x:foo)', /(?:foo)/mi.to_s)
    assert_equal('(?mix:foo)', /(?:foo)/mix.to_s)
    assert_equal('(?m-ix:foo)', /(?m-ix:foo)/.to_s)
    assert_equal('(?mi-x:foo)', /(?mi-x:foo)/.to_s)
    assert_equal('(?mix:foo)', /(?mix:foo)/.to_s)
    assert_equal('(?mix:)', /(?mix)/.to_s)
    assert_equal('(?-mix:(?mix:foo) )', /(?mix:foo) /.to_s)
  end

  def test_casefold_p
    assert_equal(false, /a/.casefold?)
    assert_equal(true, /a/i.casefold?)
    assert_equal(false, /(?i:a)/.casefold?)
  end

  def test_options
    assert_equal(Regexp::IGNORECASE, /a/i.options)
    assert_equal(Regexp::EXTENDED, /a/x.options)
    assert_equal(Regexp::MULTILINE, /a/m.options)
  end

  def test_match_init_copy
    m = /foo/.match("foo")
    assert_raise(TypeError) do
      m.instance_eval { initialize_copy(nil) }
    end
    assert_equal([0, 3], m.offset(0))
  end

  def test_match_size
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
    assert_equal(5, m.size)
  end

  def test_match_array
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foobarbaz", "foo", "bar", "baz", nil], m.to_a)
  end

  def test_match_captures
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foo", "bar", "baz", nil], m.captures)
  end

  def test_match_aref
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal("foo", m[1])
    assert_equal(["foo", "bar", "baz"], m[1..3])
    assert_nil(m[5])
  end

  def test_match_values_at
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foo", "bar", "baz"], m.values_at(1, 2, 3))
  end

  def test_match_inspect
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    #assert_equal('#<MatchData "foobarbaz" 1:"foo" 2:"bar" 3:"baz" 4:nil>', m.inspect) # Ruby 1.8.7 has much better inspect capability; this test currently fails 1.8.6.
  end

  def test_initialize
    assert_raise(ArgumentError) { Regexp.new }
    assert_equal(/foo/, Regexp.new(/foo/, Regexp::IGNORECASE))
    re = /foo/
    assert_raise(SecurityError) do
      Thread.new { $SAFE = 4; re.instance_eval { initialize(re) } }.join
    end
    re.taint
    assert_raise(SecurityError) do
      Thread.new { $SAFE = 4; re.instance_eval { initialize(re) } }.join
    end

    assert_equal("bar", "foobarbaz"[Regexp.new("b..", nil, "n")])
    assert_equal(//n, Regexp.new("", nil, "n"))

    assert_raise(RegexpError) { Regexp.new(")(") }
  end

  def test_unescape
    assert_raise(RegexpError) { s = '\\'; /#{ s }/ }
    assert_equal(/\xFF/n, /#{ s="\\xFF" }/n)
    assert_equal(/\177/, (s = '\177'; /#{ s }/))

    assert_raise(RegexpError) { s = '\x'; /#{ s }/ }

    assert_equal("\xe1", [0x00, 0xe1, 0xff].pack("C*")[/\M-a/])
    assert_equal("\xdc", [0x00, 0xdc, 0xff].pack("C*")[/\M-\\/])
    #assert_equal("\x8a", [0x00, 0x8a, 0xff].pack("C*")[/\M-\n/])
    #assert_equal("\x89", [0x00, 0x89, 0xff].pack("C*")[/\M-\t/])
    #assert_equal("\x8d", [0x00, 0x8d, 0xff].pack("C*")[/\M-\r/])
    #assert_equal("\x8c", [0x00, 0x8c, 0xff].pack("C*")[/\M-\f/])
    #assert_equal("\x8b", [0x00, 0x8b, 0xff].pack("C*")[/\M-\v/])
    #assert_equal("\x87", [0x00, 0x87, 0xff].pack("C*")[/\M-\a/])
    #assert_equal("\x9b", [0x00, 0x9b, 0xff].pack("C*")[/\M-\e/])
    assert_equal("\x01", [0x00, 0x01, 0xff].pack("C*")[/\C-a/])

    assert_raise(RegexpError) { s = '\M'; /#{ s }/ }
    #assert_raise(RegexpError) { s = '\M-\M-a'; /#{ s }/ }
    assert_raise(RegexpError) { s = '\M-\\'; /#{ s }/ }

    assert_raise(RegexpError) { s = '\C'; /#{ s }/ }
    assert_raise(RegexpError) { s = '\c'; /#{ s }/ }
    #assert_raise(RegexpError) { s = '\C-\C-a'; /#{ s }/ }

    #assert_raise(RegexpError) { s = '\M-\z'; /#{ s }/ }
    #assert_raise(RegexpError) { s = '\M-\777'; /#{ s }/ }

    s = ".........."
    5.times { s.sub!(".", "") }
    assert_equal(".....", s)
  end

  def test_equal
    assert_equal(true, /abc/ == /abc/)
    assert_equal(false, /abc/ == /abc/m)
    assert_equal(false, /abc/ == /abd/)
  end

  def test_match
    assert_nil(//.match(nil))
    assert_raise(TypeError) { /.../.match(Object.new)[0] }

    $_ = "abc"; assert_equal(1, ~/bc/)
    $_ = "abc"; assert_nil(~/d/)
    $_ = nil; assert_nil(~/./)
  end

  def test_eqq
    assert_equal(false, /../ === nil)
  end

  def test_quote
    assert_equal("\xff", Regexp.quote([0xff].pack("C")))
    assert_equal("\\ ", Regexp.quote("\ "))
    assert_equal("\\t", Regexp.quote("\t"))
    assert_equal("\\n", Regexp.quote("\n"))
    assert_equal("\\r", Regexp.quote("\r"))
    assert_equal("\\f", Regexp.quote("\f"))
    assert_equal("\\t\xff", Regexp.quote("\t" + [0xff].pack("C")))
  end

#  def test_try_convert
#    assert_equal(/re/, Regexp.try_convert(/re/))
#    assert_nil(Regexp.try_convert("re"))
#
#    o = Object.new
#    assert_nil(Regexp.try_convert(o))
#    def o.to_regexp() /foo/ end
#    assert_equal(/foo/, Regexp.try_convert(o))
#  end

  def test_union2
    assert_equal(/(?!)/, Regexp.union)
    assert_equal(/foo/, Regexp.union(/foo/))
    #assert_equal(/foo/, Regexp.union([/foo/]))
    assert_equal(/\t/, Regexp.union("\t"))
  end

  def test_dup
    assert_equal(//, //.dup)
    assert_raise(TypeError) { //.instance_eval { initialize_copy(nil) } }
  end

  def test_regsub
    assert_equal("fooXXXbaz", "foobarbaz".sub!(/bar/, "XXX"))
    s = [0xff].pack("C")
    assert_equal(s, "X".sub!(/./, s))
    assert_equal('\\' + s, "X".sub!(/./, '\\' + s))
    assert_equal('\k', "foo".sub!(/.../, '\k'))
    assert_equal('foo[bar]baz', "foobarbaz".sub!(/(b..)/, '[\0]'))
    assert_equal('foo[foo]baz', "foobarbaz".sub!(/(b..)/, '[\`]'))
    assert_equal('foo[baz]baz', "foobarbaz".sub!(/(b..)/, '[\\\']'))
    assert_equal('foo[r]baz', "foobarbaz".sub!(/(b)(.)(.)/, '[\+]'))
    assert_equal('foo[\\]baz', "foobarbaz".sub!(/(b..)/, '[\\\\]'))
    assert_equal('foo[\z]baz', "foobarbaz".sub!(/(b..)/, '[\z]'))
  end

  def test_KCODE
    assert_nothing_raised { $KCODE = 'n' }
    assert_equal('NONE', $KCODE)
    assert_equal(false, $=)
    assert_nothing_raised { $= = nil }
  end

  def test_match_setter
    /foo/ =~ "foo"
    m = $~
    /bar/ =~ "bar"
    $~ = m
    assert_equal("foo", $&)
  end

  def test_last_match
    /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal("foobarbaz", Regexp.last_match(0))
    assert_equal("foo", Regexp.last_match(1))
    assert_nil(Regexp.last_match(5))
    assert_nil(Regexp.last_match(-1))
  end

  def test_getter
    alias $__REGEXP_TEST_LASTMATCH__ $&
    alias $__REGEXP_TEST_PREMATCH__ $`
    alias $__REGEXP_TEST_POSTMATCH__ $'
    alias $__REGEXP_TEST_LASTPARENMATCH__ $+
    /(b)(.)(.)/.match("foobarbaz")
    assert_equal("bar", $__REGEXP_TEST_LASTMATCH__)
    assert_equal("foo", $__REGEXP_TEST_PREMATCH__)
    assert_equal("baz", $__REGEXP_TEST_POSTMATCH__)
    assert_equal("r", $__REGEXP_TEST_LASTPARENMATCH__)

    /(...)(...)(...)/.match("foobarbaz")
    assert_equal("baz", $+)
  end

  def test_taint
    m = Thread.new do
      "foo"[/foo/]
      $SAFE = 4
      /foo/.match("foo")
    end.value
    assert(m.tainted?)
    assert_nothing_raised('[ruby-core:26137]') {
      m = proc {$SAFE = 4; %r"#{ }"o}.call
    }
    assert(m.tainted?)
  end

  def check(re, ss, fs = [])
    re = Regexp.new(re) unless re.is_a?(Regexp)
    ss = [ss] unless ss.is_a?(Array)
    ss.each do |e, s|
      s ||= e
      assert_match(re, s)
      m = re.match(s)
      assert_equal(e, m[0])
    end
    fs = [fs] unless fs.is_a?(Array)
    fs.each {|s| assert_no_match(re, s) }
  end

  def failcheck(re)
    assert_raise(RegexpError) { %r"#{ re }" }
  end

  def test_parse
    check(/\*\+\?\{\}\|\(\)\<\>\`\'/, "*+?{}|()<>`'")
    check(/\A\w\W\z/, %w(a. b!), %w(.. ab))
    check(/\A.\b.\b.\B.\B.\z/, %w(a.aaa .a...), %w(aaaaa .....))
    check(/\A\s\S\z/, [' a', "\n."], ['  ', "\n\n", 'a '])
    check(/\A\d\D\z/, '0a', %w(00 aa))
    check(/\Afoo\Z\s\z/, "foo\n", ["foo", "foo\nbar"])
    assert_equal(%w(a b c), "abc def".scan(/\G\w/))
    check(/\A(..)\1\z/, %w(abab ....), %w(abba aba))
    check(/\A\77\z/, "?")
    check(/\A\78\z/, "\7" + '8', ["\100", ""])
    check(/\A\Qfoo\E\z/, "QfooE")
    failcheck('\Aa++\z')
    check('\Ax]\z', "x]")
    check(/x#foo/x, "x", "#foo")
    check(/\Ax#foo#{ "\n" }x\z/x, "xx", ["x", "x#foo\nx"])
    check(/\A\n\z/, "\n")
    check(/\A\t\z/, "\t")
    check(/\A\r\z/, "\r")
    check(/\A\f\z/, "\f")
    check(/\A\a\z/, "\007")
    check(/\A\e\z/, "\033")
    check(/\A\v\z/, "\v")
    failcheck('(')
    failcheck('(?foo)')
    failcheck('/[1-\w]/')
  end

  def test_exec
    check(/A*B/, %w(B AB AAB AAAB), %w(A))
    check(/\w*!/, %w(! a! ab! abc!), %w(abc))
    check(/\w*\W/, %w(! a" ab# abc$), %w(abc))
    check(/\w*\w/, %w(z az abz abcz), %w(!))
    check(/[a-z]*\w/, %w(z az abz abcz), %w(!))
    check(/[a-z]*\W/, %w(! a" ab# abc$), %w(A))
    check(/((a|bb|ccc|dddd)(1|22|333|4444))/i, %w(a1 bb1 a22), %w(a2 b1))
    check(/abc\B.\Bxyz/, %w(abcXxyz abc0xyz), %w(abc|xyz abc-xyz))
    check(/\Bxyz/, [%w(xyz abcXxyz), %w(xyz abc0xyz)], %w(abc xyz abc-xyz))
    check(/abc\B/, [%w(abc abcXxyz), %w(abc abc0xyz)], %w(abc xyz abc-xyz))
    failcheck('(?<foo>abc)\1')
    check(eval('/^(?:a?)?$/'), ["", "a"], ["aa"])
    check(eval('/^(?:a+)?$/'), ["", "a", "aa"], ["ab"])
    check(/^a??[ab]/, [["a", "a"], ["a", "aa"], ["b", "b"], ["a", "ab"]], ["c"])
    check(/^(?:a*){3,5}$/, ["", "a", "aa", "aaa", "aaaa", "aaaaa", "aaaaaa"], ["b"])
    check(/^(?:a+){3,5}$/, ["aaa", "aaaa", "aaaaa", "aaaaaa"], ["", "a", "aa", "b"])
  end

  def test_parse_curly_brace
    check(/\Aa{0}+\z/, "", %w(a aa aab))
    check(/\Aa{1}+\z/, %w(a aa), ["", "aab"])
    check(/\Aa{1,2}b{1,2}\z/, %w(ab aab abb aabb), ["", "aaabb", "abbb"])
    check(/(?!x){0,1}/, [ ['', 'ab'], ['', ''] ])
    failcheck('.{100001}')
    failcheck('.{0,100001}')
    failcheck('.{1,0}')
    failcheck('{0}')
  end

  def test_char_class
    failcheck('[]')
    failcheck('[x')
    check('\A[]]\z', "]", "")
    check('\A[]\.]+\z', %w(] . ]..]), ["", "["])
    check(/\A[abc]+\z/, "abcba", ["", "ada"])
    check(/\A[\w][\W]\z/, %w(a. b!), %w(.. ab))
    check(/\A[\s][\S]\z/, [' a', "\n."], ['  ', "\n\n", 'a '])
    check(/\A[\d][\D]\z/, '0a', %w(00 aa))
    check(/\A[\xff]\z/, "\xff", ["", "\xfe"])
    check(/\A[\80]+\z/, "8008", ["\\80", "\100", "\1000"])
    check(/\A[\77]+\z/, "???")
    check(/\A[\78]+\z/, "\788\7")
    check(/\A[\0]\z/, "\0")
    check(/\A[0-]\z/, ["0", "-"], "0-")
    check('\A[--0]\z', ["-", "/", "0"], ["", "1"])
    check('\A[\'--0]\z', %w(* + \( \) 0 ,), ["", ".", "1"])
    check(/\A[a-b-]\z/, %w(a b -), ["", "c"])
    check(/\A[\n\r\t]\z/, ["\n", "\r", "\t"])
    failcheck('[9-1]')

    assert_match(/\A\d+\z/, "0123456789")
    assert_match(/\A\w+\z/, "09azAZ_")
    #assert_match(/\A\s+\z/, "\r\n\v\f\r\s")
  end

  def test_posix_bracket
    check(/\A[[:alpha:]0]\z/, %w(0 a), %w(1 .))
    check('\A[[:abcdefghijklmnopqrstu:]]+\z', "[]")
    failcheck('[[:alpha')
    failcheck('[[:alpha:')
    failcheck('[[:alp:]]')
  end

  def test_backward
    assert_equal(3, "foobar".rindex(/b.r/i))
    assert_equal(nil, "foovar".rindex(/b.r/i))
    assert_equal(3, ("foo" + "bar" * 1000).rindex(/#{"bar"*1000}/))
    assert_equal(4, ("foo\nbar\nbaz\n").rindex(/bar/i))
  end

  def test_uninitialized
    assert_raise(TypeError) { Regexp.allocate.hash }
    assert_raise(TypeError) { Regexp.allocate.eql? Regexp.allocate }
    assert_raise(TypeError) { Regexp.allocate == Regexp.allocate }
    assert_raise(TypeError) { Regexp.allocate =~ "" }
    assert_equal(false, Regexp.allocate === Regexp.allocate)
    assert_nil(~Regexp.allocate)
    assert_raise(TypeError) { Regexp.allocate.match("") }
    assert_raise(TypeError) { Regexp.allocate.to_s }
    assert_raise(TypeError) { Regexp.allocate.inspect }
    assert_raise(TypeError) { Regexp.allocate.source }
    assert_raise(TypeError) { Regexp.allocate.casefold? }
    assert_raise(TypeError) { Regexp.allocate.options }

    assert_raise(TypeError) { MatchData.allocate.size }
    assert_raise(TypeError) { MatchData.allocate.length }
    assert_raise(TypeError) { MatchData.allocate.offset(0) }
    assert_raise(TypeError) { MatchData.allocate.begin(0) }
    assert_raise(TypeError) { MatchData.allocate.end(0) }
    assert_raise(TypeError) { MatchData.allocate.to_a }
    assert_raise(TypeError) { MatchData.allocate[:foo] }
    assert_raise(TypeError) { MatchData.allocate.values_at }
    assert_raise(TypeError) { MatchData.allocate.pre_match }
    assert_raise(TypeError) { MatchData.allocate.post_match }
    assert_raise(TypeError) { MatchData.allocate.to_s }
    assert_raise(TypeError) { MatchData.allocate.string }
    $~ = MatchData.allocate
    assert_raise(TypeError) { $& }
    assert_raise(TypeError) { $` }
    assert_raise(TypeError) { $' }
    assert_raise(TypeError) { $+ }
  end

  def test_regexp_poped
    assert_nothing_raised { eval("a = 1; /\#{ a }/; a") }
    assert_nothing_raised { eval("a = 1; /\#{ a }/o; a") }
  end

  def test_optimize_last_anycharstar
    s = "1" + " " * 5000000
    assert_nothing_raised { s.match(/(\d) (.*)/) }
    assert_equal("1", $1)
    assert_equal(" " * 4999999, $2)
  end

  def test_range_greedy
    /wo{0,3}?/ =~ "woo"
    assert_equal("w", $&)
  end
end
