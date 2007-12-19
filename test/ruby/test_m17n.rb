require 'test/unit'

class TestM17N < Test::Unit::TestCase
  def assert_encoding(encname, actual, message=nil)
    assert_equal(Encoding.find(encname), actual, message)
  end

  module AESU
    def a(str) str.dup.force_encoding("ASCII-8BIT") end
    def e(str) str.dup.force_encoding("EUC-JP") end
    def s(str) str.dup.force_encoding("Shift_JIS") end
    def u(str) str.dup.force_encoding("UTF-8") end
  end
  include AESU
  extend AESU

  def assert_strenc(bytes, enc, actual, message=nil)
    assert_instance_of(String, actual, message)
    enc = Encoding.find(enc) if String === enc
    assert_equal(enc, actual.encoding, message)
    assert_equal(a(bytes), a(actual), message)
  end

  def test_string_ascii_literal
    assert_encoding("ASCII-8BIT", eval(a(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(a(%{"a"})).encoding)
  end

  def test_string_eucjp_literal
    assert_encoding("ASCII-8BIT", eval(e(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"a"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\xa1\xa1"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\xa1\\xa1"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\x20"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\n"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\x80"})).encoding)
  end

  def test_string_mixed_unicode
    assert_raise(SyntaxError) { eval(a(%{"\xc2\xa0\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(e(%{"\xc2\xa0\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(s(%{"\xc2\xa0\\u{6666}"})) }
    assert_nothing_raised { eval(u(%{"\xc2\xa0\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(a(%{"\\u{6666}\xc2\xa0"})) }
    assert_raise(SyntaxError) { eval(e(%{"\\u{6666}\xc2\xa0"})) }
    assert_raise(SyntaxError) { eval(s(%{"\\u{6666}\xc2\xa0"})) }
    assert_nothing_raised { eval(u(%{"\\u{6666}\xc2\xa0"})) }
  end

  def test_string_inspect
    assert_equal('"\xFE"', e("\xfe").inspect)
    assert_equal('"\x8E"', e("\x8e").inspect)
    assert_equal('"\x8F"', e("\x8f").inspect)
    assert_equal('"\x8F\xA1"', e("\x8f\xa1").inspect)
    assert_equal('"\xEF"', s("\xef").inspect)
    assert_equal('"\xC2"', u("\xc2").inspect)
    assert_equal('"\xE0\x80"', u("\xe0\x80").inspect)
    assert_equal('"\xF0\x80\x80"', u("\xf0\x80\x80").inspect)
    assert_equal('"\xF8\x80\x80\x80"', u("\xf8\x80\x80\x80").inspect)
    assert_equal('"\xFC\x80\x80\x80\x80"', u("\xfc\x80\x80\x80\x80").inspect)

    assert_equal('"\xFE "', e("\xfe ").inspect)
    assert_equal('"\x8E "', e("\x8e ").inspect)
    assert_equal('"\x8F "', e("\x8f ").inspect)
    assert_equal('"\x8F\xA1 "', e("\x8f\xa1 ").inspect)
    assert_equal('"\xEF "', s("\xef ").inspect)
    assert_equal('"\xC2 "', u("\xc2 ").inspect)
    assert_equal('"\xE0\x80 "', u("\xe0\x80 ").inspect)
    assert_equal('"\xF0\x80\x80 "', u("\xf0\x80\x80 ").inspect)
    assert_equal('"\xF8\x80\x80\x80 "', u("\xf8\x80\x80\x80 ").inspect)
    assert_equal('"\xFC\x80\x80\x80\x80 "', u("\xfc\x80\x80\x80\x80 ").inspect)


    assert_equal(e("\"\\xA1\x8f\xA1\xA1\""), e("\xa1\x8f\xa1\xa1").inspect)

    assert_equal('"\x81."', s("\x81.").inspect)
    assert_equal(s("\"\x81@\""), s("\x81@").inspect)

    assert_equal('"\xFC"', u("\xfc").inspect)
  end

  def test_validate_redundant_utf8
    bits_0x10ffff = "11110100 10001111 10111111 10111111"
    [
      "0xxxxxxx",
      "110XXXXx 10xxxxxx",
      "1110XXXX 10Xxxxxx 10xxxxxx",
      "11110XXX 10XXxxxx 10xxxxxx 10xxxxxx",
      "111110XX 10XXXxxx 10xxxxxx 10xxxxxx 10xxxxxx",
      "1111110X 10XXXXxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx",
      "11111110 10XXXXXx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx",
      "11111111 10XXXXXX 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx",
    ].each {|pat0|
      [
        pat0.gsub(/x/, '1'),
        pat0.gsub(/x/, '0')
      ].each {|pat1|
        [
          pat1.sub(/X([^X]*)\z/, '1\1').gsub(/X/, "0"),
          pat1.gsub(/X/, "1"),
        ].each {|pat2|
          s = [pat2.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
          if pat2 <= bits_0x10ffff
            assert(s.valid_encoding?, "#{pat2}")
          else
            assert(!s.valid_encoding?, "#{pat2}")
          end
        }
        if / / =~ pat0
          pat3 = pat1.gsub(/X/, "0")
          s = [pat3.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
          assert(!s.valid_encoding?, "#{pat3}")
        end
      }
    }
  end

  def test_validate_surrogate
    #  1110XXXX 10Xxxxxx 10xxxxxx : 3 bytes UTF-8
    pats = [
      "11101101 10011111 10111111", # just before surrogate high
      "11101101 1010xxxx 10xxxxxx", # surrogate high
      "11101101 1011xxxx 10xxxxxx", # surrogate low
      "11101110 10000000 10000000", # just after surrogate low
    ]
    pats.values_at(1,2).each {|pat0|
      [
        pat0.gsub(/x/, '0'),
        pat0.gsub(/x/, '1'),
      ].each {|pat1|
        s = [pat1.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
        assert(!s.valid_encoding?, "#{pat1}")
      }
    }
    pats.values_at(0,3).each {|pat|
      s = [pat.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
      assert(s.valid_encoding?, "#{pat}")
    }
  end

  def test_regexp_too_short_multibyte_character
    assert_raise(SyntaxError) { eval('/\xfe/e') }
    assert_raise(SyntaxError) { eval('/\x8e/e') }
    assert_raise(SyntaxError) { eval('/\x8f/e') }
    assert_raise(SyntaxError) { eval('/\x8f\xa1/e') }
    assert_raise(SyntaxError) { eval('/\xef/s') }
    assert_raise(SyntaxError) { eval('/\xc2/u') }
    assert_raise(SyntaxError) { eval('/\xe0\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf0\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf8\x80\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xfc\x80\x80\x80\x80/u') }

    # raw 8bit
    assert_raise(SyntaxError) { eval("/\xfe/e") }
    assert_raise(SyntaxError) { eval("/\xc2/u") }

    # invalid suffix
    assert_raise(SyntaxError) { eval('/\xc2\xff/u') }
    assert_raise(SyntaxError) { eval('/\xc2 /u') }
    assert_raise(SyntaxError) { eval('/\xc2\x20/u') }
  end

  def assert_regexp_generic_encoding(r)
    assert(!r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Shift_JIS UTF-8].each {|ename|
      # "\xc2\xa1" is a valid sequence for ASCII-8BIT, EUC-JP, Shift_JIS and UTF-8.
      assert_nothing_raised { r =~ "\xc2\xa1".force_encoding(ename) }
    }
  end

  def assert_regexp_fixed_encoding(r)
    assert(r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Shift_JIS UTF-8].each {|ename|
      enc = Encoding.find(ename)
      if enc == r.encoding
        assert_nothing_raised { r =~ "\xc2\xa1".force_encoding(enc) }
      else
        assert_raise(ArgumentError) { r =~ "\xc2\xa1".force_encoding(enc) }
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
    assert_regexp_generic_ascii(Regexp.new(e("a")))
    assert_regexp_generic_ascii(Regexp.new(s("a")))
    assert_regexp_generic_ascii(Regexp.new(u("a")))

    [/a/, Regexp.new(a("a"))].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_equal(nil, r =~ a("\xc2\xa1"))
      assert_equal(nil, r =~ e("\xc2\xa1"))
      assert_equal(nil, r =~ s("\xc2\xa1"))
      assert_equal(nil, r =~ u("\xc2\xa1"))
    }
  end

  def test_regexp_ascii
    assert_regexp_fixed_ascii8bit(/a/n)
    assert_regexp_fixed_ascii8bit(/\xc2\xa1/n)
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/})))
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/n})))
    assert_regexp_fixed_ascii8bit(eval(a(%q{/\xc2\xa1/})))

    [/a/n].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_equal(nil, r =~ a("\xc2\xa1"))
      assert_raise(ArgumentError) { r =~ e("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ s("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc2\xa1") }
    }

    [/\xc2\xa1/n, eval(a(%{/\xc2\xa1/})), eval(a(%{/\xc2\xa1/n}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_equal(0, r =~ a("\xc2\xa1"))
      assert_raise(ArgumentError) { r =~ e("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ s("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc2\xa1") }
    }
  end

  def test_regexp_euc
    assert_regexp_fixed_eucjp(/a/e)
    assert_regexp_fixed_eucjp(/\xc2\xa1/e)
    assert_regexp_fixed_eucjp(eval(e(%{/\xc2\xa1/})))
    assert_regexp_fixed_eucjp(eval(e(%q{/\xc2\xa1/})))

    [/a/e].each {|r|
      assert_equal(0, r =~ a("a"))
      assert_equal(0, r =~ e("a"))
      assert_equal(0, r =~ s("a"))
      assert_equal(0, r =~ u("a"))
      assert_raise(ArgumentError) { r =~ a("\xc2\xa1") }
      assert_equal(nil, r =~ e("\xc2\xa1"))
      assert_raise(ArgumentError) { r =~ s("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc2\xa1") }
    }

    [/\xc2\xa1/e, eval(e(%{/\xc2\xa1/})), eval(e(%q{/\xc2\xa1/}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_raise(ArgumentError) { r =~ a("\xc2\xa1") }
      assert_equal(0, r =~ e("\xc2\xa1"))
      assert_raise(ArgumentError) { r =~ s("\xc2\xa1") }
      assert_raise(ArgumentError) { r =~ u("\xc2\xa1") }
    }
  end

  def test_regexp_sjis
    assert_regexp_fixed_sjis(/a/s)
    assert_regexp_fixed_sjis(/\xc2\xa1/s)
    assert_regexp_fixed_sjis(eval(s(%{/\xc2\xa1/})))
    assert_regexp_fixed_sjis(eval(s(%q{/\xc2\xa1/})))
  end

  def test_regexp_embed
    r = eval(e("/\xc2\xa1/"))
    assert_raise(ArgumentError) { eval(s("/\xc2\xa1\#{r}/s")) }
    assert_raise(ArgumentError) { eval(s("/\#{r}\xc2\xa1/s")) }

    r = /\xc2\xa1/e
    #assert_raise(ArgumentError) { eval(s("/\xc2\xa1\#{r}/s")) }
    #assert_raise(ArgumentError) { eval(s("/\#{r}\xc2\xa1/s")) }

    r = eval(e("/\xc2\xa1/"))
    #assert_raise(ArgumentError) { /\xc2\xa1#{r}/s }

    r = /\xc2\xa1/e
    #assert_raise(ArgumentError) { /\xc2\xa1#{r}/s }
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

    assert_encoding("ASCII-8BIT", Regexp.quote(a("\xc2\xa1")).encoding)
    assert_encoding("EUC-JP",     Regexp.quote(e("\xc2\xa1")).encoding)
    assert_encoding("Shift_JIS",  Regexp.quote(s("\xc2\xa1")).encoding)
    assert_encoding("UTF-8",      Regexp.quote(u("\xc2\xa1")).encoding)
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
    assert_regexp_fixed_ascii8bit(Regexp.union(a("\xc2\xa1")))
    assert_regexp_fixed_eucjp(Regexp.union(e("\xc2\xa1")))
    assert_regexp_fixed_sjis(Regexp.union(s("\xc2\xa1")))
    assert_regexp_fixed_utf8(Regexp.union(u("\xc2\xa1")))
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
      a("\xc2\xa1"), e("\xc2\xa1"), s("\xc2\xa1"), u("\xc2\xa1")
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

  def test_dynamic_ascii_regexp
    assert_regexp_fixed_ascii8bit(/#{}/n)
    assert_regexp_fixed_ascii8bit(/#{}\xc2\xa1/n)
    assert_regexp_fixed_ascii8bit(/\xc2\xa1#{}/n)
    #assert_raise(SyntaxError) { s1, s2 = s('\xc2'), s('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_eucjp_regexp
    assert_regexp_fixed_eucjp(/#{}/e)
    assert_regexp_fixed_eucjp(/#{}\xc2\xa1/e)
    assert_regexp_fixed_eucjp(/\xc2\xa1#{}/e)
    assert_raise(SyntaxError) { eval('/\xc2#{}/e') }
    assert_raise(SyntaxError) { eval('/#{}\xc2/e') }
    assert_raise(SyntaxError) { eval('/\xc2#{}\xa1/e') }
    #assert_raise(SyntaxError) { s1, s2 = e('\xc2'), e('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_sjis_regexp
    assert_regexp_fixed_sjis(/#{}/s)
    assert_regexp_fixed_sjis(/#{}\xc2\xa1/s)
    assert_regexp_fixed_sjis(/\xc2\xa1#{}/s)
    assert_raise(SyntaxError) { eval('/\x81#{}/s') }
    assert_raise(SyntaxError) { eval('/#{}\x81/s') }
    assert_raise(SyntaxError) { eval('/\x81#{}\xa1/s') }
    #assert_raise(SyntaxError) { s1, s2 = s('\x81'), s('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_utf8_regexp
    assert_regexp_fixed_utf8(/#{}/u)
    assert_regexp_fixed_utf8(/#{}\xc2\xa1/u)
    assert_regexp_fixed_utf8(/\xc2\xa1#{}/u)
    assert_raise(SyntaxError) { eval('/\xc2#{}/u') }
    assert_raise(SyntaxError) { eval('/#{}\xc2/u') }
    assert_raise(SyntaxError) { eval('/\xc2#{}\xa1/u') }
    #assert_raise(SyntaxError) { s1, s2 = u('\xc2'), u('\xa1'); /#{s1}#{s2}/ }
  end

  def test_regexp_unicode
    assert_nothing_raised { eval '/\u{0}/u' }
    assert_nothing_raised { eval '/\u{D7FF}/u' }
    assert_raise(SyntaxError) { eval '/\u{D800}/u' }
    assert_raise(SyntaxError) { eval '/\u{DFFF}/u' }
    assert_nothing_raised { eval '/\u{E000}/u' }
    assert_nothing_raised { eval '/\u{10FFFF}/u' }
    assert_raise(SyntaxError) { eval '/\u{110000}/u' }
  end

  def test_regexp_mixed_unicode
    assert_raise(SyntaxError) { eval(a(%{/\xc2\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\xc2\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\xc2\xa0\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\xc2\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}\xc2\xa0/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}\xc2\xa0/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}\xc2\xa0/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}\xc2\xa0/})) }

    assert_raise(SyntaxError) { eval(a(%{/\\xc2\\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\xc2\\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\xc2\\xa0\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\\xc2\\xa0\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}\\xc2\\xa0/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}\\xc2\\xa0/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}\\xc2\\xa0/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}\\xc2\\xa0/})) }

    assert_raise(SyntaxError) { eval(a(%{/\xc2\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\xc2\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\xc2\xa0#{}\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\xc2\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{}\xc2\xa0/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{}\xc2\xa0/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{}\xc2\xa0/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{}\xc2\xa0/})) }

    assert_raise(SyntaxError) { eval(a(%{/\\xc2\\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\xc2\\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\xc2\\xa0#{}\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\\xc2\\xa0#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{}\\xc2\\xa0/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{}\\xc2\\xa0/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{}\\xc2\\xa0/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{}\\xc2\\xa0/})) }
  end

  STRINGS = [
    a(""), e(""), s(""), u(""),
    a("a"), e("a"), s("a"), u("a"),

    # single character
    a("\x80"),
    e("\xa1\xa1"), e("\x8e\xa1"), e("\x8f\xa1\xa1"),
    s("\x81\x40"), e("\xa1"),
    u("\xc2\x80"),

    # same byte sequence
    a("\xc2\xa1"), e("\xc2\xa1"), s("\xc2\xa1"), u("\xc2\xa1"),

    s("\x81A"), # mutibyte character which contains "A"
    s("\x81a"), # mutibyte character which contains "a"

    # invalid
    e("\xa1"),
    s("\x81"),
    u("\xc2"),
  ]

  def combination(*args)
    if args.empty?
      yield []
    else
      arg = args.shift
      arg.each {|v|
        combination(*args) {|vs|
          yield [v, *vs]
        }
      }
    end
  end

  def test_str_new
    STRINGS.each {|s|
      t = String.new(s)
      assert_strenc(a(s), s.encoding, t)
    }
  end

  def is_ascii_only?(str)
    /\A[\x00-\x7f]*\z/ =~ str.dup.force_encoding("ASCII-8BIT") ? true : false
  end

  def assert_str_enc_propagation(t, s1, s2)
    if !is_ascii_only?(s1)
      assert_equal(s1.encoding, t.encoding)
    elsif !is_ascii_only?(s2)
      assert_equal(s2.encoding, t.encoding)
    else
      assert([s1.encoding, s2.encoding].include?(t.encoding))
    end
  end

  def test_str_plus
    combination(STRINGS, STRINGS) {|s1, s2|
      if s1.encoding != s2.encoding && !is_ascii_only?(s1) && !is_ascii_only?(s2)
        assert_raise(ArgumentError) { s1 + s2 }
      else
        t = s1 + s2
        assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
        assert_equal(a(s1) + a(s2), a(t))
        assert_str_enc_propagation(t, s1, s2)
      end
    }
  end

  def test_str_times
    STRINGS.each {|s|
      [0,1,2].each {|n|
        t = s * n
        assert(t.valid_encoding?) if s.valid_encoding?
        assert_strenc(a(s) * n, s.encoding, t)
      }
    }
  end

  def test_sprintf_c
    assert_strenc("\x80", 'ASCII-8BIT', a("%c") % 128)
    #assert_raise(ArgumentError) { a("%c") % 0xc2a1 }
    assert_strenc("\xc2\xa1", 'EUC-JP', e("%c") % 0xc2a1)
    assert_raise(ArgumentError) { e("%c") % 0xc2 }
    assert_strenc("\xc2", 'Shift_JIS', s("%c") % 0xc2)
    #assert_raise(ArgumentError) { s("%c") % 0xc2a1 }
    assert_strenc("\u{c2a1}", 'UTF-8', u("%c") % 0xc2a1)
    assert_strenc("\u{c2}", 'UTF-8', u("%c") % 0xc2)
  end

  def test_sprintf_s
    STRINGS.each {|s|
      assert_strenc(a(s), s.encoding, "%s".force_encoding(s.encoding) % s)
      if !s.empty? # xxx
        assert_strenc(a(s), s.encoding, a("%s") % s)
      end
    }
  end

  def test_sprintf_p
    assert_strenc('""', 'ASCII-8BIT', a("%p") % a(""))
    assert_strenc('""', 'EUC-JP', e("%p") % e(""))
    assert_strenc('""', 'Shift_JIS', s("%p") % s(""))
    assert_strenc('""', 'UTF-8', u("%p") % u(""))

    assert_strenc('"a"', 'ASCII-8BIT', a("%p") % a("a"))
    assert_strenc('"a"', 'EUC-JP', e("%p") % e("a"))
    assert_strenc('"a"', 'Shift_JIS', s("%p") % s("a"))
    assert_strenc('"a"', 'UTF-8', u("%p") % u("a"))

    assert_strenc('"\xC2\xA1"', 'ASCII-8BIT', a("%p") % a("\xc2\xa1"))
    assert_strenc("\"\xC2\xA1\"", 'EUC-JP', e("%p") % e("\xc2\xa1"))
    #assert_strenc("\"\xC2\xA1\"", 'Shift_JIS', s("%p") % s("\xc2\xa1"))
    assert_strenc("\"\xC2\xA1\"", 'UTF-8', u("%p") % u("\xc2\xa1"))

    assert_strenc('"\x00"', 'ASCII-8BIT', a("%p") % a("\x00"))
    assert_strenc('"\x00"', 'EUC-JP', e("%p") % e("\x00"))
    assert_strenc('"\x00"', 'Shift_JIS', s("%p") % s("\x00"))
    assert_strenc('"\x00"', 'UTF-8', u("%p") % u("\x00"))
  end

  def test_str_eq
    combination(STRINGS, STRINGS) {|s1, s2|
      if is_ascii_only?(s1) && is_ascii_only?(s2) && a(s1) == a(s2)
        assert(s1 == s2)
      elsif s1.encoding == s2.encoding && a(s1) == a(s2)
        assert(s1 == s2)
        assert(!(s1 != s2))
        assert_equal(0, s1 <=> s2)
      else
        assert(!(s1 == s2))
        assert(s1 != s2)
        assert_not_equal(0, s1 <=> s2)
      end
    }
  end

  def test_str_lt
    assert(a("a") < a("\xa1"))
    assert(a("a") < s("\xa1"))
    assert(s("a") < a("\xa1"))
  end

  def test_str_concat
    combination(STRINGS, STRINGS) {|s1, s2|
      s = s1.dup
      if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
        s << s2
        assert(s.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
        assert_equal(a(s), a(s1) + a(s2))
        assert_str_enc_propagation(s, s1, s2)
      else
        assert_raise(ArgumentError) { s << s2 }
      end
    }
  end

  def test_str_aref
    assert_equal(a("\xc2"), a("\xc2\xa1")[0])
    assert_equal(a("\xa1"), a("\xc2\xa1")[1])
    assert_equal(nil,       a("\xc2\xa1")[2])
    assert_equal(e("\xc2\xa1"), e("\xc2\xa1")[0])
    assert_equal(nil,           e("\xc2\xa1")[1])
    assert_equal(s("\xc2"), s("\xc2\xa1")[0])
    assert_equal(s("\xa1"), s("\xc2\xa1")[1])
    assert_equal(nil,       s("\xc2\xa1")[2])
    assert_equal(u("\xc2\xa1"), u("\xc2\xa1")[0])
    assert_equal(nil,           u("\xc2\xa1")[1])

    STRINGS.each {|s|
      t = ''
      0.upto(s.length-1) {|i|
        u = s[i]
        assert(u.valid_encoding?) if s.valid_encoding?
        t << u
      }
      assert_equal(t, s)
    }

  end

  def test_str_aref_len
    assert_equal(a("\xa1"), a("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 1])
    assert_equal(a("\xa1\xc2"), a("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 2])

    assert_equal(e("\xc2\xa2"), e("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 1])
    assert_equal(e("\xc2\xa2\xc2\xa3"), e("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 2])

    assert_equal(s("\xa1"), s("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 1])
    assert_equal(s("\xa1\xc2"), s("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 2])

    assert_equal(u("\xc2\xa2"), u("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 1])
    assert_equal(u("\xc2\xa2\xc2\xa3"), u("\xc2\xa1\xc2\xa2\xc2\xa3")[1, 2])

    STRINGS.each {|s|
      t = ''
      0.upto(s.length-1) {|i|
        u = s[i,1]
        assert(u.valid_encoding?) if s.valid_encoding?
        t << u
      }
      assert_equal(t, s)
    }

    STRINGS.each {|s|
      t = ''
      0.step(s.length-1, 2) {|i|
        u = s[i,2]
        assert(u.valid_encoding?) if s.valid_encoding?
        t << u
      }
      assert_equal(t, s)
    }
  end

  def test_str_aref_substr
    assert_equal(a("\xa1\xc2"), a("\xc2\xa1\xc2\xa2\xc2\xa3")[a("\xa1\xc2")])
    assert_raise(ArgumentError) { a("\xc2\xa1\xc2\xa2\xc2\xa3")[e("\xa1\xc2")] }

    assert_equal(nil, e("\xc2\xa1\xc2\xa2\xc2\xa3")[e("\xa1\xc2")])
    assert_raise(ArgumentError) { e("\xc2\xa1\xc2\xa2\xc2\xa3")[s("\xa1\xc2")] }

    assert_equal(s("\xa1\xc2"), s("\xc2\xa1\xc2\xa2\xc2\xa3")[s("\xa1\xc2")])
    assert_raise(ArgumentError) { s("\xc2\xa1\xc2\xa2\xc2\xa3")[u("\xa1\xc2")] }

    assert_equal(nil, u("\xc2\xa1\xc2\xa2\xc2\xa3")[u("\xa1\xc2")])
    assert_raise(ArgumentError) { u("\xc2\xa1\xc2\xa2\xc2\xa3")[a("\xa1\xc2")] }

    combination(STRINGS, STRINGS) {|s1, s2|
      if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
        t = s1[s2]
        if t != nil
          assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
          assert_equal(s2, t)
          assert_match(/#{Regexp.escape(s2)}/, s1)
        end
      else
        assert_raise(ArgumentError) { s1[s2] }
      end
    }
  end

  def test_str_aref_range2
    combination(STRINGS, -2..2, -2..2) {|s, first, last|
      t = s[first..last]
      if first < 0
        first += s.length
        if first < 0
          assert_nil(t, "#{s.inspect}[#{first}..#{last}]")
          next
        end
      end
      if s.length < first
        assert_nil(t, "#{s.inspect}[#{first}..#{last}]")
        next
      end
      assert(t.valid_encoding?) if s.valid_encoding?
      if last < 0
        last += s.length
      end
      t2 = ''
      first.upto(last) {|i|
        c = s[i]
        t2 << c if c
      }
      assert_equal(t2, t, "#{s.inspect}[#{first}..#{last}]")
    }
  end

  def test_str_aref_range3
    combination(STRINGS, -2..2, -2..2) {|s, first, last|
      t = s[first...last]
      if first < 0
        first += s.length
        if first < 0
          assert_nil(t, "#{s.inspect}[#{first}..#{last}]")
          next
        end
      end
      if s.length < first
        assert_nil(t, "#{s.inspect}[#{first}..#{last}]")
        next
      end
      if last < 0
        last += s.length
      end
      assert(t.valid_encoding?) if s.valid_encoding?
      t2 = ''
      first.upto(last-1) {|i|
        c = s[i]
        t2 << c if c
      }
      assert_equal(t2, t, "#{s.inspect}[#{first}..#{last}]")
    }
  end

  def encdump(str)
    "#{str.dump}.force_encoding(#{str.encoding.name.dump})"
  end

  def test_str_assign
    combination(STRINGS, STRINGS) {|s1, s2|
      (-2).upto(2) {|i|
        t = s1.dup
        if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
          if i < -s1.length || s1.length < i
            assert_raise(IndexError) { t[i] = s2 }
          else
            t[i] = s2
            assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
            assert(a(t).index(a(s2)))
            if s1.valid_encoding? && s2.valid_encoding?
              if i == s1.length && s2.empty?
                assert_nil(t[i])
              elsif i < 0
                assert_equal(s2, t[i-s2.length+1,s2.length],
                  "t = #{encdump(s1)}; t[#{i}] = #{encdump(s2)}; t[#{i-s2.length+1},#{s2.length}]")
              else
                assert_equal(s2, t[i,s2.length],
                  "t = #{encdump(s1)}; t[#{i}] = #{encdump(s2)}; t[#{i},#{s2.length}]")
              end
            end
          end
        else
          assert_raise(ArgumentError) { t[i] = s2 }
        end
      }
    }
  end

  def test_str_assign_len
    combination(STRINGS, -2..2, 0..2, STRINGS) {|s1, i, len, s2|
      t = s1.dup
      if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
        if i < -s1.length || s1.length < i
          assert_raise(IndexError) { t[i,len] = s2 }
        else
          assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
          t[i,len] = s2
          assert(a(t).index(a(s2)))
          if s1.valid_encoding? && s2.valid_encoding?
            if i == s1.length && s2.empty?
              assert_nil(t[i])
            elsif i < 0
              if -i < len
                len = -i
              end
              assert_equal(s2, t[i-s2.length+len,s2.length],
                "t = #{encdump(s1)}; t[#{i},#{len}] = #{encdump(s2)}; t[#{i-s2.length+len},#{s2.length}]")
            else
              assert_equal(s2, t[i,s2.length],
                "t = #{encdump(s1)}; t[#{i},#{len}] = #{encdump(s2)}; t[#{i},#{s2.length}]")
            end
          end
        end
      else
        assert_raise(ArgumentError) { t[i,len] = s2 }
      end
    }
  end

  def test_str_assign_substr
    combination(STRINGS, STRINGS, STRINGS) {|s1, s2, s3|
      t = s1.dup
      encs = [
        !is_ascii_only?(s1) ? s1.encoding : nil,
        !is_ascii_only?(s2) ? s2.encoding : nil,
        !is_ascii_only?(s3) ? s3.encoding : nil].uniq.compact
      if 1 < encs.length
        assert_raise(ArgumentError, IndexError) { t[s2] = s3 }
      else
        if encs.empty?
          encs = [
            s1.encoding,
            s2.encoding,
            s3.encoding].uniq.reject {|e| e == Encoding.find("ASCII-8BIT") }
          if encs.empty?
            encs = [Encoding.find("ASCII-8BIT")]
          end
        end
        if !t[s2]
        else
          t[s2] = s3
          assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding? && s3.valid_encoding?
        end
      end
    }
  end

  def test_str_assign_range2
    combination(STRINGS, -2..2, -2..2, STRINGS) {|s1, first, last, s2|
      t = s1.dup
      if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
        if first < -s1.length || s1.length < first
          assert_raise(RangeError) { t[first..last] = s2 }
        else
          t[first..last] = s2
          assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
          assert(a(t).index(a(s2)))
          if s1.valid_encoding? && s2.valid_encoding?
            if first < 0
              assert_equal(s2, t[s1.length+first, s2.length])
            else
              assert_equal(s2, t[first, s2.length])
            end
          end
        end
      else
        assert_raise(ArgumentError, RangeError,
                     "t=#{encdump(s1)};t[#{first}..#{last}]=#{encdump(s2)}") {
          t[first..last] = s2
        }
      end
    }
  end

  def test_str_assign_range3
    combination(STRINGS, -2..2, -2..2, STRINGS) {|s1, first, last, s2|
      t = s1.dup
      if is_ascii_only?(s1) || is_ascii_only?(s2) || s1.encoding == s2.encoding
        if first < -s1.length || s1.length < first
          assert_raise(RangeError) { t[first...last] = s2 }
        else
          t[first...last] = s2
          assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
          assert(a(t).index(a(s2)))
          if s1.valid_encoding? && s2.valid_encoding?
            if first < 0
              assert_equal(s2, t[s1.length+first, s2.length])
            else
              assert_equal(s2, t[first, s2.length])
            end
          end
        end
      else
        assert_raise(ArgumentError, RangeError,
                     "t=#{encdump(s1)};t[#{first}...#{last}]=#{encdump(s2)}") {
          t[first...last] = s2
        }
      end
    }
  end

  def test_str_cmp
    combination(STRINGS, STRINGS) {|s1, s2|
      r = s1 <=> s2
      if s1 == s2
        assert_equal(0, r)
      else
        assert_not_equal(0, r)
      end
    }
  end

  def test_str_capitalize
    STRINGS.each {|s|
      begin
        t1 = s.capitalize
      rescue ArgumentError
        assert(!s.valid_encoding?)
        next
      end
      assert(t1.valid_encoding?) if s.valid_encoding?
      t2 = s.dup
      t2.capitalize!
      assert_equal(t1, t2)
      assert_equal(s.downcase.sub(/\A[a-z]/) {|ch| a(ch).upcase }, t1)
    }
  end

  def test_str_casecmp
    combination(STRINGS, STRINGS) {|s1, s2|
      #puts "#{encdump(s1)}.casecmp(#{encdump(s2)})"
      begin
        r = s1.casecmp(s2)
      rescue ArgumentError
        assert(!s1.valid_encoding? || !s2.valid_encoding?)
        next
      end
      #assert_equal(s1.upcase <=> s2.upcase, r)
    }
  end

  def test_str_center
    assert_encoding("EUC-JP", "a".center(5, "\xa1\xa2".force_encoding("euc-jp")).encoding)

    combination(STRINGS, [0,1,2,3,10]) {|s1, width|
      t = s1.center(width)
      assert(a(t).index(a(s1)))
    }
    combination(STRINGS, [0,1,2,3,10], STRINGS) {|s1, width, s2|
      if s2.empty?
        assert_raise(ArgumentError) { s1.center(width, s2) }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.center(width, s2) }
        next
      end
      t = s1.center(width, s2)
      assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
      assert(a(t).index(a(s1)))
      assert_str_enc_propagation(t, s1, s2) if (t != s1)
    }
  end

  def test_str_ljust
    combination(STRINGS, [0,1,2,3,10]) {|s1, width|
      t = s1.ljust(width)
      assert(a(t).index(a(s1)))
    }
    combination(STRINGS, [0,1,2,3,10], STRINGS) {|s1, width, s2|
      if s2.empty?
        assert_raise(ArgumentError) { s1.ljust(width, s2) }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.ljust(width, s2) }
        next
      end
      t = s1.ljust(width, s2)
      assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
      assert(a(t).index(a(s1)))
      assert_str_enc_propagation(t, s1, s2) if (t != s1)
    }
  end

  def test_str_rjust
    combination(STRINGS, [0,1,2,3,10]) {|s1, width|
      t = s1.rjust(width)
      assert(a(t).index(a(s1)))
    }
    combination(STRINGS, [0,1,2,3,10], STRINGS) {|s1, width, s2|
      if s2.empty?
        assert_raise(ArgumentError) { s1.rjust(width, s2) }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.rjust(width, s2) }
        next
      end
      t = s1.rjust(width, s2)
      assert(t.valid_encoding?) if s1.valid_encoding? && s2.valid_encoding?
      assert(a(t).index(a(s1)))
      assert_str_enc_propagation(t, s1, s2) if (t != s1)
    }
  end

  def test_str_chomp
    combination(STRINGS, STRINGS) {|s1, s2|
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.chomp(s2) }
        next
      end
      t = s1.chomp(s2)
      assert(t.valid_encoding?, "#{encdump(s1)}.chomp(#{encdump(s2)})") if s1.valid_encoding? && s2.valid_encoding?
      assert_equal(s1.encoding, t.encoding)
      t2 = s1.dup
      t2.chomp!(s2)
      assert_equal(t, t2)
    }
  end

  def test_str_chop
    STRINGS.each {|s|
      s = s.dup
      t = s.chop
      assert(t.valid_encoding?) if s.valid_encoding?
      assert(a(s).index(a(t)))
      t2 = s.dup
      t2.chop!
      assert_equal(t, t2)
    }
  end

  def test_str_clear
    STRINGS.each {|s|
      t = s.dup
      t.clear
      assert(t.valid_encoding?)
      assert(t.empty?)
    }
  end

  def test_str_clone
    STRINGS.each {|s|
      t = s.clone
      assert_equal(s, t)
      assert_equal(s.encoding, t.encoding)
      assert_equal(a(s), a(t))
    }
  end

  def test_str_dup
    STRINGS.each {|s|
      t = s.dup
      assert_equal(s, t)
      assert_equal(s.encoding, t.encoding)
      assert_equal(a(s), a(t))
    }
  end

  def test_str_count
    combination(STRINGS, STRINGS) {|s1, s2|
      if !s1.valid_encoding? || !s2.valid_encoding?
        #assert_raise(ArgumentError) { s1.count(s2) }
        #assert_nothing_raised { s1.count(s2) }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.count(s2) }
        next
      end
      n = s1.count(s2)
      n0 = a(s1).count(a(s2))
      assert_operator(n, :<=, n0)
    }
  end

  def test_str_crypt
    combination(STRINGS, STRINGS) {|str, salt|
      if a(salt).length < 2
        assert_raise(ArgumentError) { str.crypt(salt) }
        next
      end
      t = str.crypt(salt)
      assert_equal(a(str).crypt(a(salt)), t)
      assert_encoding('ASCII-8BIT', t.encoding)
    }
  end

  def test_str_delete
    combination(STRINGS, STRINGS) {|s1, s2|
      if !s1.valid_encoding? || !s2.valid_encoding?
        #assert_raise(ArgumentError) { s1.delete(s2) }
        #assert_nothing_raised { s1.delete(s2) }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.delete(s2) }
        next
      end
      t = s1.delete(s2)
      assert(t.valid_encoding?)
      assert_equal(t.encoding, s1.encoding)
      assert_operator(t.length, :<=, s1.length)
      t2 = s1.dup
      t2.delete!(s2)
      assert_equal(t, t2)
    }
  end

  def test_str_downcase
    STRINGS.each {|s|
      if !s.valid_encoding?
        #assert_raise(ArgumentError) { s.downcase }
        #assert_nothing_raised { s.downcase }
        next
      end
      t = s.downcase
      assert(t.valid_encoding?)
      assert_equal(t.encoding, s.encoding)
      assert(t.casecmp(s))
      t2 = s.dup
      t2.downcase!
      assert_equal(t, t2)
    }
  end

  def test_str_dump
    STRINGS.each {|s|
      t = s.dump
      assert(t.valid_encoding?)
      assert(is_ascii_only?(t))
      u = eval(t)
      assert_equal(a(s), a(u))
    }
  end

  def test_str_each_line
    combination(STRINGS, STRINGS) {|s1, s2|
      if !s1.valid_encoding? || !s2.valid_encoding?
        #assert_raise(ArgumentError) { s1.each_line(s2) {} }
        #assert_nothing_raised { s1.each_line(s2) {} }
        next
      end
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.each_line(s2) {} }
        next
      end
      lines = []
      s1.each_line(s2) {|line|
        assert(line.valid_encoding?)
        assert_equal(s1.encoding, line.encoding)
        lines << line
      }
      assert_equal(s1, lines.join(''))
    }
  end

  def test_str_each_byte
    STRINGS.each {|s|
      bytes = []
      s.each_byte {|b|
        bytes << b
      }
      a(s).split(//).each_with_index {|ch, i|
        assert_equal(ch.ord, bytes[i])
      }
    }
  end

  def test_str_empty?
    STRINGS.each {|s|
      if s.length == 0
        assert(s.empty?)
      else
        assert(!s.empty?)
      end
    }
  end

  def test_str_hex
    STRINGS.each {|s|
      t = s.hex
      t2 = a(s)[/\A[0-9a-fA-Fx]*/].hex
      assert_equal(t2, t)
    }
  end

  def test_str_include?
    combination(STRINGS, STRINGS) {|s1, s2|
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.include?(s2) }
        assert_raise(ArgumentError) { s1.index(s2) }
        assert_raise(ArgumentError) { s1.rindex(s2) }
        next
      end
      t = s1.include?(s2)
      if t
        assert(a(s1).include?(a(s2)))
        assert(s1.index(s2))
        assert(s1.rindex(s2))
      else
        assert(!s1.index(s2))
        assert(!s1.rindex(s2), "!#{encdump(s1)}.rindex(#{encdump(s2)})")
      end
      if s1.valid_encoding? && s2.valid_encoding?
        if t && s1.valid_encoding? && s2.valid_encoding?
          assert_match(/#{Regexp.escape(s2)}/, s1)
        else
          assert_no_match(/#{Regexp.escape(s2)}/, s1)
        end
      end
    }
  end

  def test_str_index
    combination(STRINGS, STRINGS, -2..2) {|s1, s2, pos|
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.index(s2) }
        next
      end
      t = s1.index(s2, pos)
      if !s1.valid_encoding? || !s2.valid_encoding?
        next
      end
      if t
        re = /#{Regexp.escape(s2)}/
        assert(re.match(s1, pos))
        assert_equal($`.length, t, "#{encdump s1}.index(#{encdump s2}, #{pos})")
      end
    }
  end

  def test_str_rindex
    combination(STRINGS, STRINGS, -2..2) {|s1, s2, pos|
      if !is_ascii_only?(s1) && !is_ascii_only?(s2) && s1.encoding != s2.encoding
        assert_raise(ArgumentError) { s1.rindex(s2) }
        next
      end
      t = s1.rindex(s2, pos)
      if !s1.valid_encoding? || !s2.valid_encoding?
        next
      end
      if t
        #puts "#{encdump s1}.rindex(#{encdump s2}, #{pos}) => #{t}"
        assert(a(s1).index(a(s2)))
        pos2 = pos
        pos2 += s1.length if pos < 0
        re = /\A(.{0,#{pos2}})#{Regexp.escape(s2)}/m
        assert(re.match(s1), "#{re.inspect}.match(#{encdump(s1)})")
        assert_equal($1.length, t, "#{encdump s1}.rindex(#{encdump s2}, #{pos})")
      end
    }
  end

  def test_str_insert
    combination(STRINGS, -2..2, STRINGS) {|s1, nth, s2|
      t1 = s1.dup
      t2 = s1.dup
      begin
        t1[nth, 0] = s2
      rescue ArgumentError, IndexError => e1
      end
      begin
        t2.insert(nth, s2)
      rescue ArgumentError, IndexError => e2
      end
      assert_equal(t1, t2, "t=#{encdump s1}; t.insert(#{nth},#{encdump s2}); t")
      assert_equal(e1.class, e2.class, "begin #{encdump s1}.insert(#{nth},#{encdump s2}); rescue ArgumentError, IndexError => e; e end")
    }
  end

  def test_str_intern
    STRINGS.each {|s|
      if /\0/ =~ a(s)
        assert_raise(ArgumentError) { s.intern }
      else
        sym = s.intern
        assert_equal(s, sym.to_s)
      end
    }
  end

  def test_str_length
    STRINGS.each {|s|
      assert_operator(s.length, :<=, s.bytesize)
    }
  end

  def test_str_oct
    STRINGS.each {|s|
      t = s.oct
      t2 = a(s)[/\A[0-9a-fA-FxXbB]*/].oct
      assert_equal(t2, t)
    }
  end

  def test_str_replace
    combination(STRINGS, STRINGS) {|s1, s2|
      t = s1.dup
      t.replace s2
      assert_equal(s2, t)
      assert_equal(s2.encoding, t.encoding)
    }
  end

  def test_str_reverse
    STRINGS.each {|s|
      t = s.reverse
      assert_equal(s.bytesize, t.bytesize)
      if s.valid_encoding?
        assert_equal(s, t.reverse)
      end
    }
  end

  def test_tr
    s = "\x81\x41".force_encoding("shift_jis")
    assert_equal(s.tr("A", "B"), s)
    assert_equal(s.tr_s("A", "B"), s)
  end

  def test_squeeze
    s = "\xa3\xb0\xa3\xb1\xa3\xb1\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
    assert_equal("\xa3\xb0\xa3\xb1\xa3\xb3\xa3\xb4".force_encoding("euc-jp"), s.squeeze)
  end

  def test_sub
    s = "abc".sub(/b/, "\xa1\xa1".force_encoding("euc-jp"))
    assert_encoding("EUC-JP", s.encoding)
    assert_equal(Encoding::EUC_JP, "\xa4\xa2".force_encoding("euc-jp").sub(/./, '\&').encoding)
    assert_equal(Encoding::EUC_JP, "\xa4\xa2".force_encoding("euc-jp").gsub(/./, '\&').encoding)
  end

  def test_regexp_match
    assert_equal([0,0], //.match("\xa1\xa1".force_encoding("euc-jp"),-1).offset(0))
  end
end
