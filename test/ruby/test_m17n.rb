require 'test/unit'
require 'stringio'

class TestM17N < Test::Unit::TestCase
  def assert_encoding(encname, actual, message=nil)
    assert_equal(Encoding.find(encname), actual, message)
  end

  module AESU
    def a(str) str.dup.force_encoding("ASCII-8BIT") end
    def e(str) str.dup.force_encoding("EUC-JP") end
    def s(str) str.dup.force_encoding("Windows-31J") end
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

  def assert_warning(pat, mesg=nil)
    begin
      org_stderr = $stderr
      $stderr = StringIO.new(warn = '')
      yield
    ensure
      $stderr = org_stderr
    end
    assert_match(pat, warn, mesg)
  end

  def assert_regexp_generic_encoding(r)
    assert(!r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Windows-31J UTF-8].each {|ename|
      # "\xc2\xa1" is a valid sequence for ASCII-8BIT, EUC-JP, Windows-31J and UTF-8.
      assert_nothing_raised { r =~ "\xc2\xa1".force_encoding(ename) }
    }
  end

  def assert_regexp_fixed_encoding(r)
    assert(r.fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Windows-31J UTF-8].each {|ename|
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
    assert_encoding("Windows-31J", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def assert_regexp_fixed_utf8(r)
    assert_encoding("UTF-8", r.encoding)
    assert_regexp_fixed_encoding(r)
  end

  def encdump(str)
    d = str.dump
    if /\.force_encoding\("[A-Za-z0-9.:_+-]*"\)\z/ =~ d
      d
    else
      "#{d}.force_encoding(#{str.encoding.name.dump})"
    end
  end

  def encdumpargs(args)
    r = '('
    args.each_with_index {|a, i|
      r << ',' if 0 < i
      if String === a
        r << encdump(a)
      else
        r << a.inspect
      end
    }
    r << ')'
    r
  end

  def assert_str_enc_propagation(t, s1, s2)
    if !s1.ascii_only?
      assert_equal(s1.encoding, t.encoding)
    elsif !s2.ascii_only?
      assert_equal(s2.encoding, t.encoding)
    else
      assert([s1.encoding, s2.encoding].include?(t.encoding))
    end
  end

  def assert_same_result(expected_proc, actual_proc)
    e = nil
    begin
      t = expected_proc.call
    rescue
      e = $!
    end
    if e
      assert_raise(e.class) { actual_proc.call }
    else
      assert_equal(t, actual_proc.call)
    end
  end

  def str_enc_compatible?(*strs)
    encs = []
    strs.each {|s|
      encs << s.encoding if !s.ascii_only?
    }
    encs.uniq!
    encs.length <= 1
  end

  # tests start

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
    assert_raise(SyntaxError) { eval(a(%{"\xc2\xa1\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(e(%{"\xc2\xa1\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(s(%{"\xc2\xa1\\u{6666}"})) }
    assert_nothing_raised { eval(u(%{"\xc2\xa1\\u{6666}"})) }
    assert_raise(SyntaxError) { eval(a(%{"\\u{6666}\xc2\xa1"})) }
    assert_raise(SyntaxError) { eval(e(%{"\\u{6666}\xc2\xa1"})) }
    assert_raise(SyntaxError) { eval(s(%{"\\u{6666}\xc2\xa1"})) }
    assert_nothing_raised { eval(u(%{"\\u{6666}\xc2\xa1"})) }
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

  def test_str_dump
    [
      e("\xfe"),
      e("\x8e"),
      e("\x8f"),
      e("\x8f\xa1"),
      s("\xef"),
      u("\xc2"),
      u("\xe0\x80"),
      u("\xf0\x80\x80"),
      u("\xf8\x80\x80\x80"),
      u("\xfc\x80\x80\x80\x80"),

      e("\xfe "),
      e("\x8e "),
      e("\x8f "),
      e("\x8f\xa1 "),
      s("\xef "),
      u("\xc2 "),
      u("\xe0\x80 "),
      u("\xf0\x80\x80 "),
      u("\xf8\x80\x80\x80 "),
      u("\xfc\x80\x80\x80\x80 "),


      e("\xa1\x8f\xa1\xa1"),

      s("\x81."),
      s("\x81@"),

      u("\xfc"),
      "\u3042",
      "ascii",
    ].each do |str|
      assert_equal(str, eval(str.dump), "[ruby-dev:33142]")
    end
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

  def test_regexp_ascii_none
    r = /a/n

    assert_warning(%r{regexp match /.../n against to}) {
      assert_regexp_generic_ascii(r)
    }

    assert_equal(0, r =~ a("a"))
    assert_equal(0, r =~ e("a"))
    assert_equal(0, r =~ s("a"))
    assert_equal(0, r =~ u("a"))
    assert_equal(nil, r =~ a("\xc2\xa1"))
    assert_warning(%r{regexp match /.../n against to EUC-JP string}) {
      assert_equal(nil, r =~ e("\xc2\xa1"))
    }
    assert_warning(%r{regexp match /.../n against to Windows-31J string}) {
      assert_equal(nil, r =~ s("\xc2\xa1"))
    }
    assert_warning(%r{regexp match /.../n against to UTF-8 string}) {
      assert_equal(nil, r =~ u("\xc2\xa1"))
    }

    assert_nothing_raised { eval(e("/\\x80/n")) }
  end

  def test_regexp_ascii
    assert_regexp_fixed_ascii8bit(/\xc2\xa1/n)
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/})))
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/n})))
    assert_regexp_fixed_ascii8bit(eval(a(%q{/\xc2\xa1/})))

    assert_raise(SyntaxError) { eval("/\xa1\xa1/n".force_encoding("euc-jp")) }

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

  def test_regexp_windows_31j
    begin
      Regexp.new("\xa1".force_encoding("windows-31j")) =~ "\xa1\xa1".force_encoding("euc-jp")
    rescue ArgumentError
      err = $!
    end
    assert_match(/windows-31j/i, err.message)
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
    assert_encoding("Windows-31J",  Regexp.quote(s("\xc2\xa1")).encoding)
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
    assert_warning(%r{regexp match /.../n against to}) {
      assert_regexp_generic_ascii(Regexp.union(//n))
    }
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
    assert_warning(%r{regexp match /.../n against to}) {
      assert_regexp_generic_ascii(/#{}/n)
    }
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
    assert_raise(SyntaxError) { eval(a(%{/\xc2\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\xc2\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\xc2\xa1\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\xc2\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}\xc2\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}\xc2\xa1/})) }

    assert_raise(SyntaxError) { eval(a(%{/\\xc2\\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\xc2\\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\xc2\\xa1\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\\xc2\\xa1\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}\\xc2\\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}\\xc2\\xa1/})) }

    assert_raise(SyntaxError) { eval(a(%{/\xc2\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\xc2\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\xc2\xa1#{}\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\xc2\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{}\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{}\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{}\xc2\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{}\xc2\xa1/})) }

    assert_raise(SyntaxError) { eval(a(%{/\\xc2\\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\xc2\\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\xc2\\xa1#{}\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\\xc2\\xa1#{}\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{}\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{}\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{}\\xc2\\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{}\\xc2\\xa1/})) }
  end

  def test_str_allocate
    s = String.allocate
    assert_equal(Encoding::ASCII_8BIT, s.encoding)
  end

  def test_str_String
    s = String(10)
    assert_equal(Encoding::ASCII_8BIT, s.encoding)
  end

  def test_sprintf_c
    assert_strenc("\x80", 'ASCII-8BIT', a("%c") % 128)
    #assert_raise(ArgumentError) { a("%c") % 0xc2a1 }
    assert_strenc("\xc2\xa1", 'EUC-JP', e("%c") % 0xc2a1)
    assert_raise(ArgumentError) { e("%c") % 0xc2 }
    assert_strenc("\xc2", 'Windows-31J', s("%c") % 0xc2)
    #assert_raise(ArgumentError) { s("%c") % 0xc2a1 }
    assert_strenc("\u{c2a1}", 'UTF-8', u("%c") % 0xc2a1)
    assert_strenc("\u{c2}", 'UTF-8', u("%c") % 0xc2)
    assert_raise(ArgumentError) {
      "%s%s" % [s("\xc2\xa1"), e("\xc2\xa1")]
    }
  end

  def test_sprintf_p
    assert_strenc('""', 'ASCII-8BIT', a("%p") % a(""))
    assert_strenc('""', 'EUC-JP', e("%p") % e(""))
    assert_strenc('""', 'Windows-31J', s("%p") % s(""))
    assert_strenc('""', 'UTF-8', u("%p") % u(""))

    assert_strenc('"a"', 'ASCII-8BIT', a("%p") % a("a"))
    assert_strenc('"a"', 'EUC-JP', e("%p") % e("a"))
    assert_strenc('"a"', 'Windows-31J', s("%p") % s("a"))
    assert_strenc('"a"', 'UTF-8', u("%p") % u("a"))

    assert_strenc('"\xC2\xA1"', 'ASCII-8BIT', a("%p") % a("\xc2\xa1"))
    assert_strenc("\"\xC2\xA1\"", 'EUC-JP', e("%p") % e("\xc2\xa1"))
    #assert_strenc("\"\xC2\xA1\"", 'Windows-31J', s("%p") % s("\xc2\xa1"))
    assert_strenc("\"\xC2\xA1\"", 'UTF-8', u("%p") % u("\xc2\xa1"))

    assert_strenc('"\xC2\xA1"', 'ASCII-8BIT', "%10p" % a("\xc2\xa1"))
    assert_strenc("       \"\xC2\xA1\"", 'EUC-JP', "%10p" % e("\xc2\xa1"))
    #assert_strenc("       \"\xC2\xA1\"", 'Windows-31J', "%10p" % s("\xc2\xa1"))
    assert_strenc("       \"\xC2\xA1\"", 'UTF-8', "%10p" % u("\xc2\xa1"))

    assert_strenc('"\x00"', 'ASCII-8BIT', a("%p") % a("\x00"))
    assert_strenc('"\x00"', 'EUC-JP', e("%p") % e("\x00"))
    assert_strenc('"\x00"', 'Windows-31J', s("%p") % s("\x00"))
    assert_strenc('"\x00"', 'UTF-8', u("%p") % u("\x00"))
  end

  def test_sprintf_s
    assert_strenc('', 'ASCII-8BIT', a("%s") % a(""))
    assert_strenc('', 'EUC-JP', e("%s") % e(""))
    assert_strenc('', 'Windows-31J', s("%s") % s(""))
    assert_strenc('', 'UTF-8', u("%s") % u(""))

    assert_strenc('a', 'ASCII-8BIT', a("%s") % a("a"))
    assert_strenc('a', 'EUC-JP', e("%s") % e("a"))
    assert_strenc('a', 'Windows-31J', s("%s") % s("a"))
    assert_strenc('a', 'UTF-8', u("%s") % u("a"))

    assert_strenc("\xC2\xA1", 'ASCII-8BIT', a("%s") % a("\xc2\xa1"))
    assert_strenc("\xC2\xA1", 'EUC-JP', e("%s") % e("\xc2\xa1"))
    #assert_strenc("\xC2\xA1", 'Windows-31J', s("%s") % s("\xc2\xa1"))
    assert_strenc("\xC2\xA1", 'UTF-8', u("%s") % u("\xc2\xa1"))

    assert_strenc("        \xC2\xA1", 'ASCII-8BIT', "%10s" % a("\xc2\xa1"))
    assert_strenc("         \xA1\xA1", 'EUC-JP', "%10s" % e("\xa1\xa1"))
    #assert_strenc("         \xC2\xA1", 'Windows-31J', "%10s" % s("\xc2\xa1"))
    assert_strenc("         \xC2\xA1", 'UTF-8', "%10s" % u("\xc2\xa1"))

    assert_strenc("\x00", 'ASCII-8BIT', a("%s") % a("\x00"))
    assert_strenc("\x00", 'EUC-JP', e("%s") % e("\x00"))
    assert_strenc("\x00", 'Windows-31J', s("%s") % s("\x00"))
    assert_strenc("\x00", 'UTF-8', u("%s") % u("\x00"))
    assert_equal("EUC-JP", (e("\xc2\xa1 %s") % "foo").encoding.name)
  end

  def test_str_lt
    assert(a("a") < a("\xa1"))
    assert(a("a") < s("\xa1"))
    assert(s("a") < a("\xa1"))
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
    assert_nil(e("\xa1\xa2\xa3\xa4")[e("\xa2\xa3")])
  end

  def test_aset
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s["\xb0\xa3"] = "foo"}
  end

  def test_str_center
    assert_encoding("EUC-JP", "a".center(5, e("\xa1\xa2")).encoding)
    assert_encoding("EUC-JP", e("\xa3\xb0").center(10).encoding)
  end

  def test_squeeze
    s = e("\xa3\xb0\xa3\xb1\xa3\xb1\xa3\xb3\xa3\xb4")
    assert_equal(e("\xa3\xb0\xa3\xb1\xa3\xb3\xa3\xb4"), s.squeeze)
  end

  def test_tr
    s = s("\x81\x41")
    assert_equal(s.tr("A", "B"), s)
    assert_equal(s.tr_s("A", "B"), s)

    assert_nothing_raised {
      "a".force_encoding("ASCII-8BIT").tr(a("a"), a("a"))
    }

    assert_equal(e("\xA1\xA1"), a("a").tr(a("a"), e("\xA1\xA1")))
  end

  def test_tr_s
    assert_equal("\xA1\xA1".force_encoding("EUC-JP"),
      "a".force_encoding("ASCII-8BIT").tr("a".force_encoding("ASCII-8BIT"), "\xA1\xA1".force_encoding("EUC-JP")))
  end

  def test_count
    assert_equal(0, e("\xa1\xa2").count("z"))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s.count(a("\xa3\xb0"))}
  end

  def test_delete
    assert_equal(1, e("\xa1\xa2").delete("z").length)
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s.delete(a("\xa3\xb2"))}
  end

  def test_include?
    assert_equal(false, e("\xa1\xa2\xa3\xa4").include?(e("\xa3")))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(false, s.include?(e("\xb0\xa3")))
  end

  def test_index
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_nil(s.index(e("\xb3\xa3")))
    assert_nil(e("\xa1\xa2\xa3\xa4").index(e("\xa3")))
    assert_nil(e("\xa1\xa2\xa3\xa4").rindex(e("\xa3")))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s.rindex(a("\xb1\xa3"))}
  end

  def test_next
    s1 = e("\xa1\xa1")
    s2 = s1.dup
    (94*94+94).times { s2.next! }
    assert_not_equal(s1, s2)
  end

  def test_sub
    s = "abc".sub(/b/, "\xa1\xa1".force_encoding("euc-jp"))
    assert_encoding("EUC-JP", s.encoding)
    assert_equal(Encoding::EUC_JP, "\xa4\xa2".force_encoding("euc-jp").sub(/./, '\&').encoding)
    assert_equal(Encoding::EUC_JP, "\xa4\xa2".force_encoding("euc-jp").gsub(/./, '\&').encoding)
  end

  def test_insert
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4a"), s.insert(-1, "a"))
  end

  def test_scan
    assert_equal(["a"], e("\xa1\xa2a\xa3\xa4").scan(/a/))
  end

  def test_upto
    s1 = e("\xa1\xa2")
    s2 = s("\xa1\xa2")
    assert_raise(ArgumentError){s1.upto(s2) {|x| break }}
  end

  def test_casecmp
    s1 = s("\x81\x41")
    s2 = s("\x81\x61")
    assert_not_equal(0, s1.casecmp(s2))
  end

  def test_reverse
    assert_equal(u("\xf0jihgfedcba"), u("abcdefghij\xf0").reverse)
  end

  def test_plus
    assert_raise(ArgumentError){u("\xe3\x81\x82") + a("\xa1")}
  end

  def test_chomp
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s.chomp(s("\xa3\xb4"))}
  end

  def test_gsub
    s = 'abc'
    s.ascii_only?
    s.gsub!(/b/, "\x80")
    assert_equal(false, s.ascii_only?, "[ruby-core:14566] reported by Sam Ruby")

    s = "abc".force_encoding(Encoding::ASCII_8BIT)
    t = s.gsub(/b/, "\xa1\xa1".force_encoding("euc-jp"))
    assert_equal(Encoding::ASCII_8BIT, s.encoding)

    assert_raise(ArgumentError) {
      "abc".gsub(/[ac]/) {
         $& == "a" ? "\xc2\xa1".force_encoding("euc-jp") :
                     "\xc2\xa1".force_encoding("utf-8")
      }
    }
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(e("\xa3\xb0z\xa3\xb2\xa3\xb3\xa3\xb4"), s.gsub(/\xa3\xb1/e, "z"))
  end

  def test_end_with
    s1 = s("\x81\x40")
    s2 = "@"
    assert_equal(false, s1.end_with?(s2), "#{encdump s1}.end_with?(#{encdump s2})")
  end

  def test_each_line
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(ArgumentError){s.each_line(a("\xa3\xb1")) {|l| }}
  end

  def test_each_char
    a = [e("\xa4\xa2"), "b", e("\xa4\xa4"), "c"]
    s = "\xa4\xa2b\xa4\xa4c".force_encoding("euc-jp")
    assert_equal(a, s.each_char.to_a, "[ruby-dev:33211] #{encdump s}.each_char.to_a")
  end

  def test_regexp_match
    assert_equal([0,0], //.match("\xa1\xa1".force_encoding("euc-jp"),-1).offset(0))
    assert_equal(0, // =~ :a)
  end

  def test_split
    assert_equal(e("\xa1\xa2\xa1\xa3").split(//),
                 [e("\xa1\xa2"), e("\xa1\xa3")],
                 '[ruby-dev:32452]')
  end

  def test_nonascii_method_name
     eval(e("def \xc2\xa1() @nonascii_method_name = :e end"))
     eval(u("def \xc2\xa1() @nonascii_method_name = :u end"))
     eval(e("\xc2\xa1()"))
     assert_equal(:e, @nonascii_method_name)
     eval(u("\xc2\xa1()"))
     assert_equal(:u, @nonascii_method_name)
     me = method(e("\xc2\xa1"))
     mu = method(u("\xc2\xa1"))
     assert_not_equal(me.name, mu.name)
     assert_not_equal(me.inspect, mu.inspect)
     assert_equal(e("\xc2\xa1"), me.name)
     assert_equal(u("\xc2\xa1"), mu.name)
  end

  def test_symbol
    s1 = "\xc2\xa1".force_encoding("euc-jp").intern
    s2 = "\xc2\xa1".force_encoding("utf-8").intern
    assert_not_equal(s1, s2)
  end

  def test_chr
    0.upto(255) {|b|
      assert_equal([b].pack("C"), b.chr)
    }
  end

  def test_marshal
    s1 = "\xa1\xa1".force_encoding("euc-jp")
    s2 = Marshal.load(Marshal.dump(s1))
    assert_equal(s1, s2)
  end

  def test_env
    ENV.each {|k, v|
      assert_equal(Encoding::ASCII_8BIT, k.encoding)
      assert_equal(Encoding::ASCII_8BIT, v.encoding)
    }
  end
end
