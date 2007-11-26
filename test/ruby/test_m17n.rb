require 'test/unit'

class TestM17N < Test::Unit::TestCase
  def assert_encoding(encname, actual, message=nil)
    assert_equal(Encoding.find(encname), actual, message)
  end

  def a(str) str.force_encoding("ASCII-8BIT") end
  def e(str) str.force_encoding("EUC-JP") end
  def s(str) str.force_encoding("Shift_JIS") end
  def u(str) str.force_encoding("UTF-8") end

  def test_string_ascii_literal
    assert_encoding("ASCII-8BIT", eval(a(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(a(%{"a"})).encoding)
  end

  def test_string_euc_literal
    assert_encoding("ASCII-8BIT", eval(e(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"a"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\xa1\xa1"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\xa1\\xa1"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\x20"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\n"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\x80"})).encoding)
  end

  def test_regexp_too_short_multibyte_character
    assert_raise(SyntaxError) { eval('/\xfe/e') }
    assert_raise(SyntaxError) { eval('/\x8e/e') }
    assert_raise(SyntaxError) { eval('/\x8f/e') }
    assert_raise(SyntaxError) { eval('/\x8f\xa1/e') }
    assert_raise(SyntaxError) { eval('/\xef/s') }
    assert_raise(SyntaxError) { eval('/\xc0/u') }
    assert_raise(SyntaxError) { eval('/\xe0\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf0\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf8\x80\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xfc\x80\x80\x80\x80/u') }

    # raw 8bit
    #assert_raise(SyntaxError) { eval("/\xfe/e") }
    #assert_raise(SyntaxError) { eval("/\xc0/u") }

    # invalid suffix
    #assert_raise(SyntaxError) { eval('/\xc0\xff/u') }
    #assert_raise(SyntaxError) { eval('/\xc0\x20/u') }
  end

  def assert_regexp_generic_encoding(r)
    assert(!r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Shift_JIS UTF-8].each {|ename|
      # "\xc0\xa1" is a valid sequence for ASCII-8BIT, EUC-JP, Shift_JIS and UTF-8.
      assert_nothing_raised { r =~ "\xc0\xa1".force_encoding(ename) }
    }
  end

  def assert_regexp_fixed_encoding(r)
    assert(r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Shift_JIS UTF-8].each {|ename|
      enc = Encoding.find(ename)
      if enc == r.encoding
        assert_nothing_raised { r =~ "\xc0\xa1".force_encoding(enc) }
      else
        assert_raise(ArgumentError) { r =~ "\xc0\xa1".force_encoding(enc) }
      end
    }
  end

  def assert_regexp_generic_ascii(r)
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_regexp_generic_encoding(r)
  end

  def assert_regexp_fixed_ascii8bit(r)
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def assert_regexp_fixed_eucjp(r)
    assert_encoding("EUC-JP", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def assert_regexp_fixed_sjis(r)
    assert_encoding("Shift_JIS", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def assert_regexp_fixed_utf8(r)
    assert_encoding("UTF-8", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def test_regexp_generic
    assert_regexp_generic_ascii(/a/)
    assert_regexp_generic_ascii(Regexp.new(a("a")))

    [/a/, Regexp.new(a("a"))].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_equal(nil, r =~ a("\xc0\xa1"))
      assert_equal(nil, r =~ e("\xc0\xa1"))
      assert_equal(nil, r =~ s("\xc0\xa1"))
      assert_equal(nil, r =~ u("\xc0\xa1"))
    }
  end

  def test_regexp_ascii
    assert_regexp_fixed_ascii8bit(/a/n)
    assert_regexp_fixed_ascii8bit(/\xc0\xa1/n)
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc0\xa1/})))
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc0\xa1/n})))
    # assert_regexp_fixed_ascii8bit(eval(a(%q{/\xc0\xa1/})))

    [/a/n].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_equal(nil, r =~ a("\xc0\xa1"))
      assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }
    }

    [/\xc0\xa1/n, eval(a(%{/\xc0\xa1/})), eval(a(%{/\xc0\xa1/n}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_equal(0, r =~ a("\xc0\xa1"))
      assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }
    }
  end

  def test_regexp_euc
    assert_regexp_fixed_eucjp(/a/e)
    assert_regexp_fixed_eucjp(Regexp.new(e("a")))
    assert_regexp_fixed_eucjp(/\xc0\xa1/e)
    assert_regexp_fixed_eucjp(eval(e(%{/\xc0\xa1/})))
    assert_regexp_fixed_eucjp(eval(e(%q{/\xc0\xa1/})))

    [/a/e, Regexp.new(e("a"))].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
      assert_equal(nil, r =~ e("\xc0\xa1"))
      assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }
    }

    [/\xc0\xa1/e, eval(e(%{/\xc0\xa1/})), eval(e(%q{/\xc0\xa1/}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
      assert_equal(0, r =~ e("\xc0\xa1"))
      assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }
    }
  end

  def test_regexp_sjis
    assert_regexp_fixed_sjis(/a/s)
    assert_regexp_fixed_sjis(Regexp.new(s("a")))
    assert_regexp_fixed_sjis(/\xc0\xa1/s)
    assert_regexp_fixed_sjis(eval(s(%{/\xc0\xa1/})))
    assert_regexp_fixed_sjis(eval(s(%q{/\xc0\xa1/})))
  end

  def test_begin_end_offset
    str = e("\244\242\244\244\244\246\244\250\244\252a")
    assert(/(a)/ =~ str)
    assert_equal("a", $&)
    assert_equal(5, $~.begin(0))
    assert_equal(6, $~.end(0))
    assert_equal([5,6], $~.offset(0))
    assert_equal(5, $~.begin(1))
    assert_equal(6, $~.end(1))
    assert_equal([5,6], $~.offset(1))
  end

  def test_begin_end_offset_sjis
    str = s("\x81@@")
    assert(/@/ =~ str)
    assert_equal(s("\x81@"), $`)
    assert_equal("@", $&)
    assert_equal("", $')
    assert_equal([1,2], $~.offset(0))
  end

  def test_quote
    assert_regexp_generic_ascii(/#{Regexp.quote(a("a"))}#{Regexp.quote(e("e"))}/)

    # Regexp.quote returns ASCII-8BIT string for ASCII only string
    # to make generic regexp if possible.
    assert_encoding("ASCII-8BIT", Regexp.quote(a("")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(e("")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(s("")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(u("")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(a("a")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(e("a")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(s("a")).encoding)
    assert_encoding("ASCII-8BIT", Regexp.quote(u("a")).encoding)

    assert_encoding("ASCII-8BIT", Regexp.quote(a("\xc0\xa1")).encoding)
    assert_encoding("EUC-JP",     Regexp.quote(e("\xc0\xa1")).encoding)
    assert_encoding("Shift_JIS",  Regexp.quote(s("\xc0\xa1")).encoding)
    assert_encoding("UTF-8",      Regexp.quote(u("\xc0\xa1")).encoding)
  end

  def test_union_0
    r = Regexp.union
    assert_regexp_generic_ascii(r)
    assert(r !~ a(""))
    assert(r !~ e(""))
    assert(r !~ s(""))
    assert(r !~ u(""))
  end

  def test_union_1_asciionly_string
    assert_regexp_generic_ascii(Regexp.union(a("")))
    assert_regexp_generic_ascii(Regexp.union(e("")))
    assert_regexp_generic_ascii(Regexp.union(s("")))
    assert_regexp_generic_ascii(Regexp.union(u("")))
    assert_regexp_generic_ascii(Regexp.union(a("a")))
    assert_regexp_generic_ascii(Regexp.union(e("a")))
    assert_regexp_generic_ascii(Regexp.union(s("a")))
    assert_regexp_generic_ascii(Regexp.union(u("a")))
    assert_regexp_generic_ascii(Regexp.union(a("\t")))
    assert_regexp_generic_ascii(Regexp.union(e("\t")))
    assert_regexp_generic_ascii(Regexp.union(s("\t")))
    assert_regexp_generic_ascii(Regexp.union(u("\t")))
  end

  def test_union_1_nonascii_string
    assert_regexp_fixed_ascii8bit(Regexp.union(a("\xc0\xa1")))
    assert_regexp_fixed_eucjp(Regexp.union(e("\xc0\xa1")))
    assert_regexp_fixed_sjis(Regexp.union(s("\xc0\xa1")))
    assert_regexp_fixed_utf8(Regexp.union(u("\xc0\xa1")))
  end

  def test_union_1_regexp
    assert_regexp_generic_ascii(Regexp.union(//))
    assert_regexp_fixed_ascii8bit(Regexp.union(//n))
    assert_regexp_fixed_eucjp(Regexp.union(//e))
    assert_regexp_fixed_sjis(Regexp.union(//s))
    assert_regexp_fixed_utf8(Regexp.union(//u))
  end

  def test_union_2
    ary = [
      a(""), e(""), s(""), u(""),
      a("\xc0\xa1"), e("\xc0\xa1"), s("\xc0\xa1"), u("\xc0\xa1")
    ]
    ary.each {|s1|
      ary.each {|s2|
        if s1.empty?
          if s2.empty?
            assert_regexp_generic_ascii(Regexp.union(s1, s2))
          else
            r = Regexp.union(s1, s2)
            assert_regexp_fixed_encoding(r)
            assert_equal(s2.encoding, r.encoding)
          end
        else
          if s2.empty?
            r = Regexp.union(s1, s2)
            assert_regexp_fixed_encoding(r)
            assert_equal(s1.encoding, r.encoding)
          else
            if s1.encoding == s2.encoding
              r = Regexp.union(s1, s2)
              assert_regexp_fixed_encoding(r)
              assert_equal(s1.encoding, r.encoding)
            else
              assert_raise(ArgumentError) { Regexp.union(s1, s2) }
            end
          end
        end
      }
    }
  end
end
