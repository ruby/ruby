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
    assert_equal('"\376"', e("\xfe").inspect)
    assert_equal('"\216"', e("\x8e").inspect)
    assert_equal('"\217"', e("\x8f").inspect)
    assert_equal('"\217\241"', e("\x8f\xa1").inspect)
    assert_equal('"\357"', s("\xef").inspect)
    assert_equal('"\302"', u("\xc2").inspect)
    assert_equal('"\340\200"', u("\xe0\x80").inspect)
    assert_equal('"\360\200\200"', u("\xf0\x80\x80").inspect)
    assert_equal('"\370\200\200\200"', u("\xf8\x80\x80\x80").inspect)
    assert_equal('"\374\200\200\200\200"', u("\xfc\x80\x80\x80\x80").inspect)

    assert_equal('"\376 "', e("\xfe ").inspect)
    assert_equal('"\216 "', e("\x8e ").inspect)
    assert_equal('"\217 "', e("\x8f ").inspect)
    assert_equal('"\217\241 "', e("\x8f\xa1 ").inspect)
    assert_equal('"\357 "', s("\xef ").inspect)
    assert_equal('"\302 "', u("\xc2 ").inspect)
    assert_equal('"\340\200 "', u("\xe0\x80 ").inspect)
    assert_equal('"\360\200\200 "', u("\xf0\x80\x80 ").inspect)
    assert_equal('"\370\200\200\200 "', u("\xf8\x80\x80\x80 ").inspect)
    assert_equal('"\374\200\200\200\200 "', u("\xfc\x80\x80\x80\x80 ").inspect)


    assert_equal(e("\"\\241\x8f\xa1\xa1\""), e("\xa1\x8f\xa1\xa1").inspect)

    assert_equal('"\201."', s("\x81.").inspect)
    assert_equal(s("\"\x81@\""), s("\x81@").inspect)

    assert_equal('"\374"', u("\xfc").inspect)
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
    assert_nothing_raised { eval '/\u{0}/' }
    assert_nothing_raised { eval '/\u{D7FF}/' }
    assert_raise(SyntaxError) { eval '/\u{D800}/' }
    assert_raise(SyntaxError) { eval '/\u{DFFF}/' }
    assert_nothing_raised { eval '/\u{E000}/' }
    assert_nothing_raised { eval '/\u{10FFFF}/' }
    assert_raise(SyntaxError) { eval '/\u{110000}/' }
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

  def test_tr
    s = "\x81\x41".force_encoding("shift_jis")
    assert_equal(s.tr("A", "B"), s)
    assert_equal(s.tr_s("A", "B"), s)
  end

  def test_squeeze
    s = "\xa3\xb0\xa3\xb1\xa3\xb1\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
    assert_equal("\xa3\xb0\xa3\xb1\xa3\xb3\xa3\xb4".force_encoding("euc-jp"), s.squeeze)
  end
end
