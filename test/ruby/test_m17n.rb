# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'

class TestM17N < Test::Unit::TestCase
  def assert_encoding(encname, actual, message=nil)
    assert_equal(Encoding.find(encname), actual, message)
  end

  module AESU
    def ua(str) str.dup.force_encoding("US-ASCII") end
    def a(str) str.b end
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

  def assert_regexp_generic_encoding(r)
    assert_not_predicate(r, :fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Windows-31J UTF-8].each {|ename|
      # "\xc2\xa1" is a valid sequence for ASCII-8BIT, EUC-JP, Windows-31J and UTF-8.
      assert_nothing_raised { r =~ "\xc2\xa1".force_encoding(ename) }
    }
  end

  def assert_regexp_fixed_encoding(r)
    assert_predicate(r, :fixed_encoding?)
    %w[ASCII-8BIT EUC-JP Windows-31J UTF-8].each {|ename|
      enc = Encoding.find(ename)
      if enc == r.encoding
        assert_nothing_raised { r =~ "\xc2\xa1".force_encoding(enc) }
      else
        assert_raise(Encoding::CompatibilityError) { r =~ "\xc2\xa1".force_encoding(enc) }
      end
    }
  end

  def assert_regexp_generic_ascii(r)
    assert_encoding("US-ASCII", r.encoding)
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

  def assert_regexp_usascii_literal(r, enc, ex = nil)
    code = "# -*- encoding: US-ASCII -*-\n#{r}.encoding"
    if ex
      assert_raise(ex) { eval(code) }
    else
      assert_equal(enc, eval(code))
    end
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
      assert_include([s1.encoding, s2.encoding], t.encoding)
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
    assert_encoding("EUC-JP", eval(e(%{""})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"a"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\xa1\xa1"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\xa1\\xa1"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\x20"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\n"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\x80"})).encoding)
  end

  def test_utf8_literal
    assert_equal(Encoding::UTF_8, "\u3042".encoding, "[ruby-dev:33406] \"\\u3042\".encoding")
    assert_raise(SyntaxError) { eval(a('\u3052\x80')) }
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

  def test_string_inspect_invalid
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

    assert_equal('"\x81."', s("\x81.").inspect)
    assert_equal('"\xFC"', u("\xfc").inspect)
  end

  def test_string_inspect_encoding
    EnvUtil.suppress_warning do
      begin
        orig_int = Encoding.default_internal
        orig_ext = Encoding.default_external
        Encoding.default_internal = nil
        [Encoding::UTF_8, Encoding::EUC_JP, Encoding::Windows_31J, Encoding::GB18030].
          each do |e|
          Encoding.default_external = e
          str = "\x81\x30\x81\x30".force_encoding('GB18030')
          assert_equal(Encoding::GB18030 == e ? %{"#{str}"} : '"\x{81308130}"', str.inspect)
          str = e("\xa1\x8f\xa1\xa1")
          expected = "\"\\xA1\x8F\xA1\xA1\"".force_encoding("EUC-JP")
          assert_equal(Encoding::EUC_JP == e ? expected : "\"\\xA1\\x{8FA1A1}\"", str.inspect)
          str = s("\x81@")
          assert_equal(Encoding::Windows_31J == e ? %{"#{str}"} : '"\x{8140}"', str.inspect)
          str = "\u3042\u{10FFFD}"
          assert_equal(Encoding::UTF_8 == e ? %{"#{str}"} : '"\u3042\u{10FFFD}"', str.inspect)
          end
        Encoding.default_external = Encoding::UTF_8
        [Encoding::UTF_16BE, Encoding::UTF_16LE, Encoding::UTF_32BE, Encoding::UTF_32LE,
          Encoding::UTF8_SOFTBANK].each do |e|
          str = "abc".encode(e)
          assert_equal('"abc"', str.inspect)
          end
      ensure
        Encoding.default_internal = orig_int
        Encoding.default_external = orig_ext
      end
    end
  end

  STR_WITHOUT_BOM = "\u3042".freeze
  STR_WITH_BOM = "\uFEFF\u3042".freeze
  bug8940 = '[ruby-core:59757] [Bug #8940]'
  bug9415 = '[ruby-dev:47895] [Bug #9415]'
  %w/UTF-16 UTF-32/.each do |enc|
    %w/BE LE/.each do |endian|
      bom = "\uFEFF".encode("#{enc}#{endian}").force_encoding(enc)

      define_method("test_utf_16_32_inspect(#{enc}#{endian})") do
        s = STR_WITHOUT_BOM.encode(enc + endian)
        # When a UTF-16/32 string doesn't have a BOM,
        # inspect as a dummy encoding string.
        assert_equal(s.dup.force_encoding("ISO-2022-JP").inspect,
                     s.dup.force_encoding(enc).inspect)
        assert_normal_exit("#{bom.b.dump}.force_encoding('#{enc}').inspect", bug8940)
      end

      define_method("test_utf_16_32_codepoints(#{enc}#{endian})") do
        assert_equal([0xFEFF], bom.codepoints, bug9415)
      end

      define_method("test_utf_16_32_ord(#{enc}#{endian})") do
        assert_equal(0xFEFF, bom.ord, bug9415)
      end

      define_method("test_utf_16_32_inspect(#{enc}#{endian}-BOM)") do
        s = STR_WITH_BOM.encode(enc + endian)
        # When a UTF-16/32 string has a BOM,
        # inspect as a particular encoding string.
        assert_equal(s.inspect,
                     s.dup.force_encoding(enc).inspect)
      end
    end
  end

  def test_utf_without_bom_asciionly
    bug10598 = '[ruby-core:66835] [Bug #10598]'
    encs = [Encoding::UTF_16, Encoding::UTF_32].find_all {|enc|
      "abcd".force_encoding(enc).ascii_only?
    }
    assert_empty(encs, bug10598)
  end

  def test_utf_without_bom_valid
    encs = [Encoding::UTF_16, Encoding::UTF_32].find_all {|enc|
      !(+"abcd").encode!(enc).force_encoding(enc).valid_encoding?
    }
    assert_empty(encs)
  end

  def test_object_utf16_32_inspect
    EnvUtil.suppress_warning do
      begin
        orig_int = Encoding.default_internal
        orig_ext = Encoding.default_external
        Encoding.default_internal = nil
        Encoding.default_external = Encoding::UTF_8
        o = Object.new
        [Encoding::UTF_16BE, Encoding::UTF_16LE, Encoding::UTF_32BE, Encoding::UTF_32LE].each do |e|
          o.instance_eval "undef inspect;def inspect;'abc'.encode('#{e}');end"
          assert_equal '[abc]', [o].inspect
        end
      ensure
        Encoding.default_internal = orig_int
        Encoding.default_external = orig_ext
      end
    end
  end

  def test_object_inspect_external
    orig_v, $VERBOSE = $VERBOSE, false
    orig_int, Encoding.default_internal = Encoding.default_internal, nil
    orig_ext = Encoding.default_external
    o = Object.new

    Encoding.default_external = Encoding::UTF_16BE
    def o.inspect
      "abc"
    end
    assert_nothing_raised(Encoding::CompatibilityError) { [o].inspect }

    def o.inspect
      "abc".encode(Encoding.default_external)
    end
    assert_equal '[abc]', [o].inspect

    Encoding.default_external = Encoding::US_ASCII
    def o.inspect
      "\u3042"
    end
    assert_equal '[\u3042]', [o].inspect

    def o.inspect
      "\x82\xa0".force_encoding(Encoding::Windows_31J)
    end
    assert_equal '[\x{82A0}]', [o].inspect
  ensure
    Encoding.default_internal = orig_int
    Encoding.default_external = orig_ext
    $VERBOSE = orig_v
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

      "\u3042".encode("UTF-16LE"),
      "\u3042".encode("UTF-16BE"),
    ].each do |str|
      dump = str.dump
      assert_equal(str, eval(dump), "[ruby-dev:33142]")
      assert_equal(str, dump.undump)
      assert_equal(str, eval("# frozen-string-literal: true\n#{dump}"), '[Bug #14687]')
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
            assert_predicate(s, :valid_encoding?, "#{pat2}")
          else
            assert_not_predicate(s, :valid_encoding?, "#{pat2}")
          end
        }
        if / / =~ pat0
          pat3 = pat1.gsub(/X/, "0")
          s = [pat3.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
          assert_not_predicate(s, :valid_encoding?, "#{pat3}")
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
        assert_not_predicate(s, :valid_encoding?, "#{pat1}")
      }
    }
    pats.values_at(0,3).each {|pat|
      s = [pat.gsub(/ /, "")].pack("B*").force_encoding("utf-8")
      assert_predicate(s, :valid_encoding?, "#{pat}")
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

    assert_warning(%r{historical binary regexp match /\.\.\./n against}) {
      assert_regexp_generic_ascii(r)
    }

    assert_equal(0, r =~ a("a"))
    assert_equal(0, r =~ e("a"))
    assert_equal(0, r =~ s("a"))
    assert_equal(0, r =~ u("a"))
    assert_equal(nil, r =~ a("\xc2\xa1"))
    assert_warning(%r{historical binary regexp match /\.\.\./n against EUC-JP string}) {
      assert_equal(nil, r =~ e("\xc2\xa1"))
    }
    assert_warning(%r{historical binary regexp match /\.\.\./n against Windows-31J string}) {
      assert_equal(nil, r =~ s("\xc2\xa1"))
    }
    assert_warning(%r{historical binary regexp match /\.\.\./n against UTF-8 string}) {
      assert_equal(nil, r =~ u("\xc2\xa1"))
    }

    assert_nothing_raised { eval(e("/\\x80/n")) }
  end

  def test_regexp_ascii
    assert_regexp_fixed_ascii8bit(/\xc2\xa1/n)
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/})))
    assert_regexp_fixed_ascii8bit(eval(a(%{/\xc2\xa1/n})))
    assert_regexp_fixed_ascii8bit(eval(a(%q{/\xc2\xa1/})))

    s = '\xc2\xa1'
    assert_regexp_fixed_ascii8bit(/#{s}/)

    assert_raise(SyntaxError) { eval("/\xa1\xa1/n".force_encoding("euc-jp")) }

    [/\xc2\xa1/n, eval(a(%{/\xc2\xa1/})), eval(a(%{/\xc2\xa1/n}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_equal(0, r =~ a("\xc2\xa1"))
      assert_raise(Encoding::CompatibilityError) { r =~ e("\xc2\xa1") }
      assert_raise(Encoding::CompatibilityError) { r =~ s("\xc2\xa1") }
      assert_raise(Encoding::CompatibilityError) { r =~ u("\xc2\xa1") }
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
      assert_raise(Encoding::CompatibilityError) { r =~ a("\xc2\xa1") }
      assert_equal(nil, r =~ e("\xc2\xa1"))
      assert_raise(Encoding::CompatibilityError) { r =~ s("\xc2\xa1") }
      assert_raise(Encoding::CompatibilityError) { r =~ u("\xc2\xa1") }
    }

    [/\xc2\xa1/e, eval(e(%{/\xc2\xa1/})), eval(e(%q{/\xc2\xa1/}))].each {|r|
      assert_equal(nil, r =~ a("a"))
      assert_equal(nil, r =~ e("a"))
      assert_equal(nil, r =~ s("a"))
      assert_equal(nil, r =~ u("a"))
      assert_raise(Encoding::CompatibilityError) { r =~ a("\xc2\xa1") }
      assert_equal(0, r =~ e("\xc2\xa1"))
      assert_raise(Encoding::CompatibilityError) { r =~ s("\xc2\xa1") }
      assert_raise(Encoding::CompatibilityError) { r =~ u("\xc2\xa1") }
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
    rescue Encoding::CompatibilityError
      err = $!
    end
    assert_match(/windows-31j/i, err.message)
  end

  def test_regexp_embed
    r = eval(e("/\xc2\xa1/"))
    assert_raise(RegexpError) { eval(s("/\xc2\xa1\#{r}/s")) }
    assert_raise(RegexpError) { eval(s("/\#{r}\xc2\xa1/s")) }

    r = /\xc2\xa1/e
    assert_raise(RegexpError) { eval(s("/\xc2\xa1\#{r}/s")) }
    assert_raise(RegexpError) { eval(s("/\#{r}\xc2\xa1/s")) }

    r = eval(e("/\xc2\xa1/"))
    assert_raise(RegexpError) { /\xc2\xa1#{r}/s }

    r = /\xc2\xa1/e
    assert_raise(RegexpError) { /\xc2\xa1#{r}/s }

    r1 = Regexp.new('foo'.force_encoding("ascii-8bit"))
    r2 = eval('/bar#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::US_ASCII, r2.encoding)

    r1 = Regexp.new('foo'.force_encoding("us-ascii"))
    r2 = eval('/bar#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::US_ASCII, r2.encoding)

    r1 = Regexp.new('foo'.force_encoding("ascii-8bit"))
    r2 = eval('/bar#{r1}/'.force_encoding('us-ascii'))
    assert_equal(Encoding::US_ASCII, r2.encoding)

    r1 = Regexp.new('foo'.force_encoding("us-ascii"))
    r2 = eval('/bar#{r1}/'.force_encoding('us-ascii'))
    assert_equal(Encoding::US_ASCII, r2.encoding)

    r1 = Regexp.new('\xa1'.force_encoding("ascii-8bit"))
    r2 = eval('/bar#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, r2.encoding)

    r1 = Regexp.new('\xa1'.force_encoding("ascii-8bit"))
    r2 = eval('/bar#{r1}/'.force_encoding('us-ascii'))
    assert_equal(Encoding::ASCII_8BIT, r2.encoding)

    r1 = Regexp.new('foo'.force_encoding("ascii-8bit"))
    r2 = eval('/\xa1#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, r2.encoding)

    r1 = Regexp.new('foo'.force_encoding("us-ascii"))
    r2 = eval('/\xa1#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, r2.encoding)

    r1 = Regexp.new('\xa1'.force_encoding("ascii-8bit"))
    r2 = eval('/\xa1#{r1}/'.force_encoding('ascii-8bit'))
    assert_equal(Encoding::ASCII_8BIT, r2.encoding)

    [r1, r2]
  end

  def test_regexp_named_class
    assert_match(/[[:space:]]/u, "\u{00a0}")
    assert_match(/[[:space:]]/, "\u{00a0}")
  end

  def test_regexp_property
    s = '\p{Hiragana}'.force_encoding("euc-jp")
    assert_equal(Encoding::EUC_JP, s.encoding)
    r = nil
    assert_nothing_raised {
      r = Regexp.new(s)
    }
    assert_predicate(r, :fixed_encoding?)
    assert_match(r, "\xa4\xa2".force_encoding("euc-jp"))

    r = eval('/\p{Hiragana}/'.force_encoding("euc-jp"))
    assert_predicate(r, :fixed_encoding?)
    assert_match(r, "\xa4\xa2".force_encoding("euc-jp"))

    r = /\p{Hiragana}/e
    assert_predicate(r, :fixed_encoding?)
    assert_match(r, "\xa4\xa2".force_encoding("euc-jp"))

    r = /\p{AsciI}/e
    assert_predicate(r, :fixed_encoding?)
    assert_match(r, "a".force_encoding("euc-jp"))

    r = /\p{hiraganA}/e
    assert_predicate(r, :fixed_encoding?)
    assert_match(r, "\xa4\xa2".force_encoding("euc-jp"))

    r = eval('/\u{3042}\p{Hiragana}/'.force_encoding("euc-jp"))
    assert_predicate(r, :fixed_encoding?)
    assert_equal(Encoding::UTF_8, r.encoding)

    r = eval('/\p{Hiragana}\u{3042}/'.force_encoding("euc-jp"))
    assert_predicate(r, :fixed_encoding?)
    assert_equal(Encoding::UTF_8, r.encoding)
  end

  def test_regexp_embed_preprocess
    r1 = /\xa4\xa2/e
    r2 = /#{r1}/
    assert_include(r2.source, r1.source)
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

    assert_encoding("US-ASCII", Regexp.quote(a("")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(e("")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(s("")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(u("")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(a("a")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(e("a")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(s("a")).encoding)
    assert_encoding("US-ASCII", Regexp.quote(u("a")).encoding)

    assert_encoding("ASCII-8BIT", Regexp.quote(a("\xc2\xa1")).encoding)
    assert_encoding("EUC-JP",     Regexp.quote(e("\xc2\xa1")).encoding)
    assert_encoding("Windows-31J",  Regexp.quote(s("\xc2\xa1")).encoding)
    assert_encoding("UTF-8",      Regexp.quote(u("\xc2\xa1")).encoding)
  end

  def test_union_0
    r = Regexp.union
    assert_regexp_generic_ascii(r)
    assert_not_match(r, a(""))
    assert_not_match(r, e(""))
    assert_not_match(r, s(""))
    assert_not_match(r, u(""))
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
    assert_warning(%r{historical binary regexp match /.../n against}) {
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
    assert_warning(%r{historical binary regexp match /.../n against}) {
      assert_regexp_generic_ascii(/#{ }/n)
    }
    assert_regexp_fixed_ascii8bit(/#{ }\xc2\xa1/n)
    assert_regexp_fixed_ascii8bit(/\xc2\xa1#{ }/n)
    assert_nothing_raised { s1, s2 = a('\xc2'), a('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_eucjp_regexp
    assert_regexp_fixed_eucjp(/#{ }/e)
    assert_regexp_fixed_eucjp(/#{ }\xc2\xa1/e)
    assert_regexp_fixed_eucjp(/\xc2\xa1#{ }/e)
    assert_raise(SyntaxError) { eval('/\xc2#{ }/e') }
    assert_raise(SyntaxError) { eval('/#{ }\xc2/e') }
    assert_raise(SyntaxError) { eval('/\xc2#{ }\xa1/e') }
    assert_raise(ArgumentError) { s1, s2 = e('\xc2'), e('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_sjis_regexp
    assert_regexp_fixed_sjis(/#{ }/s)
    assert_regexp_fixed_sjis(/#{ }\xc2\xa1/s)
    assert_regexp_fixed_sjis(/\xc2\xa1#{ }/s)
    assert_raise(SyntaxError) { eval('/\x81#{ }/s') }
    assert_raise(SyntaxError) { eval('/#{ }\x81/s') }
    assert_raise(SyntaxError) { eval('/\x81#{ }\xa1/s') }
    assert_raise(ArgumentError) { s1, s2 = s('\x81'), s('\xa1'); /#{s1}#{s2}/ }
  end

  def test_dynamic_utf8_regexp
    assert_regexp_fixed_utf8(/#{ }/u)
    assert_regexp_fixed_utf8(/#{ }\xc2\xa1/u)
    assert_regexp_fixed_utf8(/\xc2\xa1#{ }/u)
    assert_raise(SyntaxError) { eval('/\xc2#{ }/u') }
    assert_raise(SyntaxError) { eval('/#{ }\xc2/u') }
    assert_raise(SyntaxError) { eval('/\xc2#{ }\xa1/u') }
    assert_raise(ArgumentError) { s1, s2 = u('\xc2'), u('\xa1'); /#{s1}#{s2}/ }
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

    assert_raise(SyntaxError) { eval(a(%{/\xc2\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\xc2\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\xc2\xa1#{ }\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\xc2\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{ }\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{ }\xc2\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{ }\xc2\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{ }\xc2\xa1/})) }

    assert_raise(SyntaxError) { eval(a(%{/\\xc2\\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\xc2\\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\xc2\\xa1#{ }\\u{6666}/})) }
    assert_nothing_raised { eval(u(%{/\\xc2\\xa1#{ }\\u{6666}/})) }
    assert_raise(SyntaxError) { eval(a(%{/\\u{6666}#{ }\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(e(%{/\\u{6666}#{ }\\xc2\\xa1/})) }
    assert_raise(SyntaxError) { eval(s(%{/\\u{6666}#{ }\\xc2\\xa1/})) }
    assert_nothing_raised { eval(u(%{/\\u{6666}#{ }\\xc2\\xa1/})) }
  end

  def test_str_allocate
    s = String.allocate
    assert_equal(Encoding::ASCII_8BIT, s.encoding)
  end

  def test_str_String
    s = String(10)
    assert_equal(Encoding::US_ASCII, s.encoding)
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
    assert_raise(Encoding::CompatibilityError) {
      "%s%s" % [s("\xc2\xa1"), e("\xc2\xa1")]
    }
  end

  def test_sprintf_p
    Encoding.list.each do |e|
      format = "%p".force_encoding(e)
      ['', 'a', "\xC2\xA1", "\x00"].each do |s|
        s.force_encoding(e)
        enc = (''.force_encoding(e) + s.inspect).encoding
        assert_strenc(s.inspect, enc, format % s)
      end
      s = "\xC2\xA1".force_encoding(e)
      enc = ('' + s.inspect).encoding
      assert_strenc('%10s' % s.inspect, enc, "%10p" % s)
    end
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
    assert_operator(a("a"), :<, a("\xa1"))
    assert_operator(a("a"), :<, s("\xa1"))
    assert_operator(s("a"), :<, a("\xa1"))
  end

  def test_str_multiply
    str = "\u3042"
    assert_equal(true,  (str * 0).ascii_only?, "[ruby-dev:33895]")
    assert_equal(false, (str * 1).ascii_only?)
    assert_equal(false, (str * 2).ascii_only?)
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

    str = "\u3042"
    assert_equal(true,  str[0, 0].ascii_only?, "[ruby-dev:33895]")
    assert_equal(false, str[0, 1].ascii_only?)
    assert_equal(false, str[0..-1].ascii_only?)
  end

  def test_utf8str_aref
    s = "abcdefghijklmnopqrstuvwxyz\u{3042 3044 3046 3048 304A}"
    assert_equal("a", s[0])
    assert_equal("h", s[7])
    assert_equal("i", s[8])
    assert_equal("j", s[9])
    assert_equal("\u{3044}", s[27])
    assert_equal("\u{3046}", s[28])
    assert_equal("\u{3048}", s[29])
    s = "abcdefghijklmnopqrstuvw\u{3042 3044 3046 3048 304A}"
    assert_equal("\u{3044}", s[24])
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
    assert_raise(Encoding::CompatibilityError) { a("\xc2\xa1\xc2\xa2\xc2\xa3")[e("\xa1\xc2")] }

    assert_equal(nil, e("\xc2\xa1\xc2\xa2\xc2\xa3")[e("\xa1\xc2")])
    assert_raise(Encoding::CompatibilityError) { e("\xc2\xa1\xc2\xa2\xc2\xa3")[s("\xa1\xc2")] }

    assert_equal(s("\xa1\xc2"), s("\xc2\xa1\xc2\xa2\xc2\xa3")[s("\xa1\xc2")])
    assert_raise(Encoding::CompatibilityError) { s("\xc2\xa1\xc2\xa2\xc2\xa3")[u("\xa1\xc2")] }

    assert_equal(nil, u("\xc2\xa1\xc2\xa2\xc2\xa3")[u("\xa1\xc2")])
    assert_raise(Encoding::CompatibilityError) { u("\xc2\xa1\xc2\xa2\xc2\xa3")[a("\xa1\xc2")] }
    assert_nil(e("\xa1\xa2\xa3\xa4")[e("\xa2\xa3")])

    bug2379 = '[ruby-core:26787]'
    assert_equal("\u{439}", "\u{439}"[0, 30], bug2379)
    assert_equal("\u{439}", "a\u{439}"[1, 30], bug2379)
    assert_equal("\u{439}", "a\u{439}bcdefghijklmnop"[1, 1][0, 1], bug2379)
  end

  def test_str_aref_force_encoding
    bug5836 = '[ruby-core:41896]'
    Encoding.list.each do |enc|
      next unless enc.ascii_compatible?
      s = "abc".force_encoding(enc)
      assert_equal("", s[3, 1], bug5836)
    end
  end

  def test_aset
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s["\xb0\xa3"] = "foo"}

    a = ua("a")
    a[/a/] = u("")
    assert_equal Encoding::US_ASCII, a.encoding
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

    assert_equal("X\u3042\u3044X", "A\u3042\u3044\u3046".tr("^\u3042\u3044", "X"))
    assert_equal("\u3042\u3046" * 100, ("\u3042\u3044" * 100).tr("\u3044", "\u3046"))
    assert_equal("Y", "\u3042".tr("^X", "Y"))
  end

  def test_tr_s
    assert_equal("\xA1\xA1".force_encoding("EUC-JP"),
      "a".force_encoding("ASCII-8BIT").tr("a".force_encoding("ASCII-8BIT"), "\xA1\xA1".force_encoding("EUC-JP")))
  end

  def test_count
    assert_equal(0, e("\xa1\xa2").count("z"))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s.count(a("\xa3\xb0"))}
  end

  def test_count_sjis_trailing_byte
    bug10078 = '[ruby-dev:48442] [Bug #10078]'
    assert_equal(0, s("\x98\x61").count("a"), bug10078)
  end

  def test_delete
    assert_equal(1, e("\xa1\xa2").delete("z").length)
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s.delete(a("\xa3\xb2"))}

    a = "\u3042\u3044\u3046\u3042\u3044\u3046"
    a.delete!("\u3042\u3044", "^\u3044")
    assert_equal("\u3044\u3046\u3044\u3046", a)
  end

  def test_include?
    assert_equal(false, e("\xa1\xa2\xa3\xa4").include?(e("\xa3")))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(false, s.include?(e("\xb0\xa3")))
    bug11488 = '[ruby-core:70592] [Bug #11488]'
    each_encoding("abcdef", "def") do |str, substr|
      assert_equal(true, str.include?(substr), bug11488)
    end
  end

  def test_index
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_nil(s.index(e("\xb3\xa3")))
    assert_nil(e("\xa1\xa2\xa3\xa4").index(e("\xa3")))
    assert_nil(e("\xa1\xa2\xa3\xa4").rindex(e("\xa3")))
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s.rindex(a("\xb1\xa3"))}
    bug11488 = '[ruby-core:70592] [Bug #11488]'
    each_encoding("abcdef", "def") do |str, substr|
      assert_equal(3, str.index(substr), bug11488)
    end
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

  def test_sub2
    s = "\x80".force_encoding("ASCII-8BIT")
    r = Regexp.new("\x80".force_encoding("ASCII-8BIT"))
    s2 = s.sub(r, "")
    assert_empty(s2)
    assert_predicate(s2, :ascii_only?)
  end

  def test_sub3
    repl = "\x81".force_encoding("sjis")
    assert_equal(false, repl.valid_encoding?)
    s = "a@".sub(/a/, repl)
    assert_predicate(s, :valid_encoding?)
  end

  def test_insert
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4a"), s.insert(-1, "a"))
  end

  def test_scan
    assert_equal(["a"], e("\xa1\xa2a\xa3\xa4").scan(/a/))
  end

  def test_dup_scan
    s1 = e("\xa4\xa2")*100
    s2 = s1.b
    s2.scan(/\A./n) {|f|
      assert_equal(Encoding::ASCII_8BIT, f.encoding)
    }
  end

  def test_dup_aref
    s1 = e("\xa4\xa2")*100
    s2 = s1.b
    assert_equal(Encoding::ASCII_8BIT, s2[10..-1].encoding)
  end

  def test_upto
    s1 = e("\xa1\xa2")
    s2 = s("\xa1\xa2")
    assert_raise(Encoding::CompatibilityError){s1.upto(s2) {|x| break }}
  end

  def test_casecmp
    s1 = s("\x81\x41")
    s2 = s("\x81\x61")
    assert_not_equal(0, s1.casecmp(s2))
  end

  def test_reverse
    bug11387 = '[ruby-dev:49189] [Bug #11387]'
    s1 = u("abcdefghij\xf0")
    s2 = s1.reverse
    assert_not_predicate(s1, :valid_encoding?, bug11387)
    assert_equal(u("\xf0jihgfedcba"), s2)
    assert_not_predicate(s2, :valid_encoding?, bug11387)
  end

  def test_reverse_bang
    s = u("abcdefghij\xf0")
    s.reverse!
    assert_equal(u("\xf0jihgfedcba"), s)
  end

  def test_plus
    assert_raise(Encoding::CompatibilityError){u("\xe3\x81\x82") + a("\xa1")}
  end

  def test_chomp
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s.chomp(s("\xa3\xb4"))}
  end

  def test_gsub
    s = 'abc'
    s.ascii_only?
    s.gsub!(/b/, "\x80")
    assert_equal(false, s.ascii_only?, "[ruby-core:14566] reported by Sam Ruby")

    s = "abc".force_encoding(Encoding::ASCII_8BIT)
    assert_equal(Encoding::ASCII_8BIT, s.encoding)

    assert_raise(Encoding::CompatibilityError) {
      "abc".gsub(/[ac]/) {
         $& == "a" ? "\xc2\xa1".force_encoding("euc-jp") :
                     "\xc2\xa1".force_encoding("utf-8")
      }
    }
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_equal(e("\xa3\xb0z\xa3\xb2\xa3\xb3\xa3\xb4"), s.gsub(/\xa3\xb1/e, "z"))

    assert_equal(Encoding::ASCII_8BIT, (a("").gsub(//) { e("") }.encoding))
    assert_equal(Encoding::ASCII_8BIT, (a("a").gsub(/a/) { e("") }.encoding))
  end

  def test_end_with
    s1 = s("\x81\x40")
    s2 = "@"
    assert_equal(false, s1.end_with?(s2), "#{encdump s1}.end_with?(#{encdump s2})")
    each_encoding("\u3042\u3044", "\u3044") do |_s1, _s2|
      assert_equal(true, _s1.end_with?(_s2), "#{encdump _s1}.end_with?(#{encdump _s2})")
    end
    each_encoding("\u3042a\u3044", "a\u3044") do |_s1, _s2|
      assert_equal(true, _s1.end_with?(_s2), "#{encdump _s1}.end_with?(#{encdump _s2})")
    end
  end

  def test_each_line
    s = e("\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4")
    assert_raise(Encoding::CompatibilityError){s.each_line(a("\xa3\xb1")) {|l| }}
    s = e("\xa4\xa2\nfoo")

    actual = []
    s.each_line {|line| actual << line }
    expected = [e("\xa4\xa2\n"), e("foo")]
    assert_equal(expected, actual)
  end

  def test_each_char
    a = [e("\xa4\xa2"), "b", e("\xa4\xa4"), "c"]
    s = "\xa4\xa2b\xa4\xa4c".force_encoding("euc-jp")
    assert_equal(a, s.each_char.to_a, "[ruby-dev:33211] #{encdump s}.each_char.to_a")
  end

  def test_str_concat
    assert_equal(1, "".concat(0xA2).size)
    assert_equal(Encoding::ASCII_8BIT, "".force_encoding("US-ASCII").concat(0xA2).encoding)
    assert_equal("A\x84\x31\xA4\x39".force_encoding("GB18030"),
                 "A".force_encoding("GB18030") << 0x8431A439)
  end

  def test_regexp_match
    assert_equal([0,0], //.match("\xa1\xa1".force_encoding("euc-jp"),-1).offset(0))
    assert_equal(0, // =~ :a)
  end

  def test_split
    assert_equal(e("\xa1\xa2\xa1\xa3").split(//),
                 [e("\xa1\xa2"), e("\xa1\xa3")],
                 '[ruby-dev:32452]')

    each_encoding("abc,def", ",", "abc", "def") do |str, sep, *expected|
      assert_equal(expected, str.split(sep, -1))
    end
    each_encoding("abc\0def", "\0", "abc", "def") do |str, sep, *expected|
      assert_equal(expected, str.split(sep, -1))
    end
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
     assert_equal(e("\xc2\xa1"), me.name.to_s)
     assert_equal(u("\xc2\xa1"), mu.name.to_s)
  end

  def test_symbol
    s1 = "\xc2\xa1".force_encoding("euc-jp").intern
    s2 = "\xc2\xa1".force_encoding("utf-8").intern
    assert_not_equal(s1, s2)
  end

  def test_symbol_op
    ops = %w"
      .. ... + - * / % ** +@ -@ | ^ & ! <=> > >= < <= ==
      === != =~ !~ ~ ! [] []= << >> :: `
    "
    ops.each do |op|
      assert_equal(Encoding::US_ASCII, op.intern.encoding, "[ruby-dev:33449]")
    end
  end

  def test_chr
    0.upto(255) {|b|
      assert_equal([b].pack("C"), b.chr)
    }
    assert_equal("\x84\x31\xA4\x39".force_encoding("GB18030"), 0x8431A439.chr("GB18030"))
    e = assert_raise(RangeError) {
      2206368128.chr(Encoding::UTF_8)
    }
    assert_not_match(/-\d+ out of char range/, e.message)

    assert_raise(RangeError){ 0x80.chr("US-ASCII") }
    assert_raise(RangeError){ 0x80.chr("SHIFT_JIS") }
    assert_raise(RangeError){ 0xE0.chr("SHIFT_JIS") }
    assert_raise(RangeError){ 0x100.chr("SHIFT_JIS") }
    assert_raise(RangeError){ 0xA0.chr("EUC-JP") }
    assert_raise(RangeError){ 0x100.chr("EUC-JP") }
    assert_raise(RangeError){ 0xA1A0.chr("EUC-JP") }
  end

  def test_marshal
    s1 = "\xa1\xa1".force_encoding("euc-jp")
    s2 = Marshal.load(Marshal.dump(s1))
    assert_equal(s1, s2)
  end

  def test_env
    locale_encoding = Encoding.find("locale")
    ENV.each {|k, v|
      assert_equal(locale_encoding, k.encoding, k)
      assert_equal(locale_encoding, v.encoding, v)
    }
  end

  def test_empty_string
    assert_equal(Encoding::US_ASCII, "".encoding)
  end

  def test_nil_to_s
    assert_equal(Encoding::US_ASCII, nil.to_s.encoding)
  end

  def test_nil_inspect
    assert_equal(Encoding::US_ASCII, nil.inspect.encoding)
  end

  def test_true_to_s
    assert_equal(Encoding::US_ASCII, true.to_s.encoding)
  end

  def test_false_to_s
    assert_equal(Encoding::US_ASCII, false.to_s.encoding)
  end

  def test_fixnum_to_s
    assert_equal(Encoding::US_ASCII, 1.to_s.encoding)
  end

  def test_float_to_s
    assert_equal(Encoding::US_ASCII, 1.0.to_s.encoding)
  end

  def test_bignum_to_s
    assert_equal(Encoding::US_ASCII, (1 << 129).to_s.encoding)
  end

  def test_array_to_s
    assert_equal(Encoding::US_ASCII, [].to_s.encoding)
    assert_equal(Encoding::US_ASCII, [nil].to_s.encoding)
    assert_equal(Encoding::US_ASCII, [1].to_s.encoding)
    assert_equal("".inspect.encoding, [""].to_s.encoding)
    assert_equal("a".inspect.encoding, ["a"].to_s.encoding)
    assert_equal(Encoding::US_ASCII, [nil,1,"","a","\x20",[]].to_s.encoding)
  end

  def test_hash_to_s
    assert_equal(Encoding::US_ASCII, {}.to_s.encoding)
    assert_equal(Encoding::US_ASCII, {1=>nil,"foo"=>""}.to_s.encoding)
  end

  def test_encoding_find
    assert_raise(TypeError) {Encoding.find(nil)}
    assert_raise(TypeError) {Encoding.find(0)}
    assert_raise(TypeError) {Encoding.find([])}
    assert_raise(TypeError) {Encoding.find({})}
  end

  def test_encoding_to_s
    assert_equal(Encoding::US_ASCII, Encoding::US_ASCII.to_s.encoding)
    assert_equal(Encoding::US_ASCII, Encoding::US_ASCII.inspect.encoding)
  end

  def test_regexp_source
    s = "\xa4\xa2".force_encoding("euc-jp")
    r = Regexp.new(s)
    t = r.source
    assert_equal(s, t, "[ruby-dev:33377] Regexp.new(#{encdump s}).source")
  end

  def test_magic_comment
    assert_equal(Encoding::US_ASCII, eval("__ENCODING__".force_encoding("US-ASCII")))
    assert_equal(Encoding::ASCII_8BIT, eval("__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::US_ASCII, eval("# -*- encoding: US-ASCII -*-\n__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::ASCII_8BIT, eval("# -*- encoding: ASCII-8BIT -*-\n__ENCODING__".force_encoding("US-ASCII")))
  end

  def test_magic_comment_vim
    assert_equal(Encoding::US_ASCII, eval("# vim: filetype=ruby, fileencoding: US-ASCII, ts=3, sw=3\n__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::ASCII_8BIT, eval("# vim: filetype=ruby, fileencoding: ASCII-8BIT, ts=3, sw=3\n__ENCODING__".force_encoding("US-ASCII")))
  end

  def test_magic_comment_at_various_positions
    # after shebang
    assert_equal(Encoding::US_ASCII, eval("#!/usr/bin/ruby\n# -*- encoding: US-ASCII -*-\n__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::ASCII_8BIT, eval("#!/usr/bin/ruby\n# -*- encoding: ASCII-8BIT -*-\n__ENCODING__".force_encoding("US-ASCII")))
    # wrong position
    assert_equal(Encoding::ASCII_8BIT, eval("\n# -*- encoding: US-ASCII -*-\n__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::US_ASCII, eval("\n# -*- encoding: ASCII-8BIT -*-\n__ENCODING__".force_encoding("US-ASCII")))

    # leading expressions
    assert_equal(Encoding::ASCII_8BIT, eval("v=1 # -*- encoding: US-ASCII -*-\n__ENCODING__".force_encoding("ASCII-8BIT")))
    assert_equal(Encoding::US_ASCII, eval("v=1 # -*- encoding: ASCII-8BIT -*-\n__ENCODING__".force_encoding("US-ASCII")))
  end

  def test_regexp_usascii
    assert_regexp_usascii_literal('//', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/#{ }/', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/#{"a"}/', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/#{%q"\x80"}/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/#{"\x80"}/', nil, SyntaxError)

    assert_regexp_usascii_literal('/a/', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/a#{ }/', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/a#{"a"}/', Encoding::US_ASCII)
    assert_regexp_usascii_literal('/a#{%q"\x80"}/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/a#{"\x80"}/', nil, SyntaxError)

    assert_regexp_usascii_literal('/\x80/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/\x80#{ }/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/\x80#{"a"}/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/\x80#{%q"\x80"}/', Encoding::ASCII_8BIT)
    assert_regexp_usascii_literal('/\x80#{"\x80"}/', nil, SyntaxError)

    assert_regexp_usascii_literal('/\u1234/', Encoding::UTF_8)
    assert_regexp_usascii_literal('/\u1234#{ }/', Encoding::UTF_8)
    assert_regexp_usascii_literal('/\u1234#{"a"}/', Encoding::UTF_8)
    assert_regexp_usascii_literal('/\u1234#{%q"\x80"}/', nil, SyntaxError)
    assert_regexp_usascii_literal('/\u1234#{"\x80"}/', nil, SyntaxError)
    assert_regexp_usascii_literal('/\u1234\x80/', nil, SyntaxError)
    assert_regexp_usascii_literal('/\u1234#{ }\x80/', nil, RegexpError)
  end

  def test_gbk
    assert_equal("", "\x81\x40".force_encoding("GBK").chop)
  end

  def test_euc_tw
    assert_equal("a", "a\x8e\xa2\xa1\xa1".force_encoding("euc-tw").chop)
  end

  def test_valid_encoding
    s = "\xa1".force_encoding("euc-jp")
    assert_equal(false, s.valid_encoding?)
    assert_equal(true, (s+s).valid_encoding?, "[ruby-dev:33826]")
    assert_equal(true, (s*2).valid_encoding?, "[ruby-dev:33826]")
    assert_equal(true, ("%s%s" % [s, s]).valid_encoding?)
    assert_equal(true, (s.dup << s).valid_encoding?)
    assert_equal(true, "".center(2, s).valid_encoding?)

    s = "\xa1\xa1\x8f".force_encoding("euc-jp")
    assert_equal(false, s.valid_encoding?)
    assert_equal(true, s.reverse.valid_encoding?)

    bug4018 = '[ruby-core:33027]'
    s = "\xa1\xa1".force_encoding("euc-jp")
    assert_equal(true, s.valid_encoding?)
    s << "\x8f".force_encoding("euc-jp")
    assert_equal(false, s.valid_encoding?, bug4018)
    s = "aa".force_encoding("utf-16be")
    assert_equal(true, s.valid_encoding?)
    s << "\xff".force_encoding("utf-16be")
    assert_equal(false, s.valid_encoding?, bug4018)

    bug6190 = '[ruby-core:43557]'
    s = "\xe9"
    s = s.encode("utf-8", "utf-8")
    assert_equal(false, s.valid_encoding?, bug6190)
    s = "\xe9"
    s.encode!("utf-8", "utf-8")
    assert_equal(false, s.valid_encoding?, bug6190)
  end

  def test_getbyte
    assert_equal(0x82, u("\xE3\x81\x82\xE3\x81\x84").getbyte(2))
    assert_equal(0x82, u("\xE3\x81\x82\xE3\x81\x84").getbyte(-4))
    assert_nil(u("\xE3\x81\x82\xE3\x81\x84").getbyte(100))
  end

  def test_setbyte
    s = u("\xE3\x81\x82\xE3\x81\x84")
    s.setbyte(2, 0x84)
    assert_equal(u("\xE3\x81\x84\xE3\x81\x84"), s)

    s = u("\xE3\x81\x82\xE3\x81\x84")
    assert_raise(IndexError) { s.setbyte(100, 0) }

    s = u("\xE3\x81\x82\xE3\x81\x84")
    s.setbyte(-4, 0x84)
    assert_equal(u("\xE3\x81\x84\xE3\x81\x84"), s)

    x = "x" * 100
    t = nil
    failure = proc {"#{i}: #{encdump(t)}"}

    s = "\u{3042 3044}"
    s.bytesize.times {|i|
      t = s + x
      t.setbyte(i, t.getbyte(i)+1)
      assert_predicate(t, :valid_encoding?, failure)
      assert_not_predicate(t, :ascii_only?, failure)
      t = s + x
      t.setbyte(i, 0x20)
      assert_not_predicate(t, :valid_encoding?, failure)
    }

    s = "\u{41 42 43}"
    s.bytesize.times {|i|
      t = s + x
      t.setbyte(i, 0x20)
      assert_predicate(t, :valid_encoding?, failure)
      assert_predicate(t, :ascii_only?, failure)
      t.setbyte(i, 0xe3)
      assert_not_predicate(t, :valid_encoding?, failure)
    }
  end

  def test_setbyte_range
    s = u("\xE3\x81\x82\xE3\x81\x84")
    assert_nothing_raised { s.setbyte(0, -1) }
    assert_nothing_raised { s.setbyte(0, 0x00) }
    assert_nothing_raised { s.setbyte(0, 0x7F) }
    assert_nothing_raised { s.setbyte(0, 0x80) }
    assert_nothing_raised { s.setbyte(0, 0xff) }
    assert_nothing_raised { s.setbyte(0, 0x100) }
    assert_nothing_raised { s.setbyte(0, 0x4f7574206f6620636861722072616e6765) }
  end

  def test_compatible
    assert_nil Encoding.compatible?("",0)
    assert_equal(Encoding::UTF_8, Encoding.compatible?(u(""), ua("abc")))
    assert_equal(Encoding::UTF_8, Encoding.compatible?(Encoding::UTF_8, Encoding::UTF_8))
    assert_equal(Encoding::UTF_8, Encoding.compatible?(Encoding::UTF_8, Encoding::US_ASCII))
    assert_equal(Encoding::ASCII_8BIT,
                 Encoding.compatible?(Encoding::ASCII_8BIT, Encoding::US_ASCII))
    assert_nil Encoding.compatible?(Encoding::UTF_8, Encoding::ASCII_8BIT)
  end

  def test_force_encoding
    assert_equal(u("\x80"), "".center(1, u("\x80")),
                 "moved from btest/knownbug, [ruby-dev:33807]")
    a = "".force_encoding("ascii-8bit") << 0xC3 << 0xB6
    assert_equal(1, a.force_encoding("utf-8").size, '[ruby-core:22437]')
    b = "".force_encoding("ascii-8bit") << 0xC3.chr << 0xB6.chr
    assert_equal(1, b.force_encoding("utf-8").size, '[ruby-core:22437]')

    assert_raise(TypeError){ ''.force_encoding(nil) }
  end

  def test_combchar_codepoint
    assert_equal([0x30BB, 0x309A], "\u30BB\u309A".codepoints.to_a)
    assert_equal([0x30BB, 0x309A], "\u30BB\u309A".codepoints.to_a)
  end

  def each_encoding(*strings)
    Encoding.list.each do |enc|
      next if enc.dummy?
      strs = strings.map {|s| s.encode(enc)} rescue next
      yield(*strs)
    end
  end

  def test_str_b
    s = "\u3042"
    assert_equal(a("\xE3\x81\x82"), s.b)
    assert_equal(Encoding::ASCII_8BIT, s.b.encoding)
    s.taint
    assert_predicate(s.b, :tainted?)
    s = "abc".b
    assert_predicate(s.b, :ascii_only?)
  end

  def test_scrub_valid_string
    str = "foo"
    assert_equal(str, str.scrub)
    assert_not_same(str, str.scrub)
    assert_predicate(str.dup.taint.scrub, :tainted?)
    str = "\u3042\u3044"
    assert_equal(str, str.scrub)
    assert_not_same(str, str.scrub)
    assert_predicate(str.dup.taint.scrub, :tainted?)
    str.force_encoding(Encoding::ISO_2022_JP) # dummy encoding
    assert_equal(str, str.scrub)
    assert_not_same(str, str.scrub)
    assert_nothing_raised(ArgumentError) {str.scrub(nil)}
    assert_predicate(str.dup.taint.scrub, :tainted?)
  end

  def test_scrub_modification_inside_block
    str = ("abc\u3042".b << "\xE3\x80".b).force_encoding('UTF-8')
    assert_raise(RuntimeError) {str.scrub{|_| str << "1234567890"; "?" }}

    str = "\x00\xD8\x42\x30".force_encoding(Encoding::UTF_16LE)
    assert_raise(RuntimeError) do
      str.scrub do |_|
        str << "1\x002\x00".force_encoding('UTF-16LE')
        "?\x00".force_encoding('UTF-16LE')
      end
    end
  end

  def test_scrub_replace_default
    assert_equal("\uFFFD\uFFFD\uFFFD", u("\x80\x80\x80").scrub)
    assert_equal("\uFFFDA", u("\xF4\x80\x80A").scrub)
    assert_predicate(u("\x80\x80\x80").taint.scrub, :tainted?)
    assert_predicate(u("\xF4\x80\x80A").taint.scrub, :tainted?)

    # examples in Unicode 6.1.0 D93b
    assert_equal("\x41\uFFFD\uFFFD\x41\uFFFD\x41",
                 u("\x41\xC0\xAF\x41\xF4\x80\x80\x41").scrub)
    assert_equal("\x41\uFFFD\uFFFD\uFFFD\x41",
                 u("\x41\xE0\x9F\x80\x41").scrub)
    assert_equal("\u0061\uFFFD\uFFFD\uFFFD\u0062\uFFFD\u0063\uFFFD\uFFFD\u0064",
                 u("\x61\xF1\x80\x80\xE1\x80\xC2\x62\x80\x63\x80\xBF\x64").scrub)
    assert_equal("abcdefghijklmnopqrstuvwxyz\u0061\uFFFD\uFFFD\uFFFD\u0062\uFFFD\u0063\uFFFD\uFFFD\u0064",
                 u("abcdefghijklmnopqrstuvwxyz\x61\xF1\x80\x80\xE1\x80\xC2\x62\x80\x63\x80\xBF\x64").scrub)
  end

  def test_scrub_replace_argument
    assert_equal("foo", u("foo").scrub("\u3013"))
    assert_predicate(u("foo").taint.scrub("\u3013"), :tainted?)
    assert_not_predicate(u("foo").scrub("\u3013".taint), :tainted?)
    assert_equal("\u3042\u3044", u("\xE3\x81\x82\xE3\x81\x84").scrub("\u3013"))
    assert_predicate(u("\xE3\x81\x82\xE3\x81\x84").taint.scrub("\u3013"), :tainted?)
    assert_not_predicate(u("\xE3\x81\x82\xE3\x81\x84").scrub("\u3013".taint), :tainted?)
    assert_equal("\u3042\u3013", u("\xE3\x81\x82\xE3\x81").scrub("\u3013"))
    assert_predicate(u("\xE3\x81\x82\xE3\x81").taint.scrub("\u3013"), :tainted?)
    assert_predicate(u("\xE3\x81\x82\xE3\x81").scrub("\u3013".taint), :tainted?)
    assert_raise(Encoding::CompatibilityError){ u("\xE3\x81\x82\xE3\x81").scrub(e("\xA4\xA2")) }
    assert_raise(TypeError){ u("\xE3\x81\x82\xE3\x81").scrub(1) }
    assert_raise(ArgumentError){ u("\xE3\x81\x82\xE3\x81\x82\xE3\x81").scrub(u("\x81")) }
    assert_equal(e("\xA4\xA2\xA2\xAE"), e("\xA4\xA2\xA4").scrub(e("\xA2\xAE")))
  end

  def test_scrub_replace_block
    assert_equal("\u3042<e381>", u("\xE3\x81\x82\xE3\x81").scrub{|x|'<'+x.unpack('H*')[0]+'>'})
    assert_predicate(u("\xE3\x81\x82\xE3\x81").taint.scrub{|x|'<'+x.unpack('H*')[0]+'>'}, :tainted?)
    assert_predicate(u("\xE3\x81\x82\xE3\x81").scrub{|x|('<'+x.unpack('H*')[0]+'>').taint}, :tainted?)
    assert_raise(Encoding::CompatibilityError){ u("\xE3\x81\x82\xE3\x81").scrub{e("\xA4\xA2")} }
    assert_raise(TypeError){ u("\xE3\x81\x82\xE3\x81").scrub{1} }
    assert_raise(ArgumentError){ u("\xE3\x81\x82\xE3\x81\x82\xE3\x81").scrub{u("\x81")} }
    assert_equal(e("\xA4\xA2\xA2\xAE"), e("\xA4\xA2\xA4").scrub{e("\xA2\xAE")})

    assert_equal(u("\x81"), u("a\x81c").scrub {|c| break c})
    assert_raise(ArgumentError) {u("a\x81").scrub {|c| c}}
    assert_raise(ArgumentError) {u("a").scrub("?") {|c| c}}
  end

  def test_scrub_widechar
    assert_equal("\uFFFD\u3042".encode("UTF-16BE"),
                 "\xD8\x00\x30\x42".force_encoding(Encoding::UTF_16BE).
                 scrub)
    assert_equal("\uFFFD\u3042".encode("UTF-16LE"),
                 "\x00\xD8\x42\x30".force_encoding(Encoding::UTF_16LE).
                 scrub)
    assert_equal("\uFFFD".encode("UTF-32BE"),
                 "\xff".force_encoding(Encoding::UTF_32BE).
                 scrub)
    assert_equal("\uFFFD".encode("UTF-32LE"),
                 "\xff".force_encoding(Encoding::UTF_32LE).
                 scrub)
    c = nil
    assert_equal("?\u3042".encode(Encoding::UTF_16LE),
                 "\x00\xD8\x42\x30".force_encoding(Encoding::UTF_16LE).
                   scrub {|e| c = e; "?".encode(Encoding::UTF_16LE)})
    assert_equal("\x00\xD8".force_encoding(Encoding::UTF_16LE), c)
    assert_raise(ArgumentError) {"\uFFFD\u3042".encode("UTF-16BE").scrub("") {}}
  end

  def test_scrub_dummy_encoding
    s = "\u{3042}".encode("iso-2022-jp")
    assert_equal(s, s.scrub)
    assert_equal(s, s.force_encoding("iso-2022-jp").scrub("?"))
  end

  def test_scrub_bang
    str = "\u3042\u3044"
    assert_same(str, str.scrub!)
    str.force_encoding(Encoding::ISO_2022_JP) # dummy encoding
    assert_same(str, str.scrub!)
    assert_nothing_raised(ArgumentError) {str.scrub!(nil)}

    str = u("\x80\x80\x80")
    str.scrub!
    assert_same(str, str.scrub!)
    assert_equal("\uFFFD\uFFFD\uFFFD", str)
  end

  def test_escaped_metachar
    bug10670 = '[ruby-core:67193] [Bug #10670]'

    escape_plain = /\A[\x5B]*\z/.freeze

    assert_match(escape_plain, 0x5b.chr(::Encoding::UTF_8), bug10670)
    assert_match(escape_plain, 0x5b.chr, bug10670)
  end

  def test_inspect_with_default_internal
    bug11787 = '[ruby-dev:49415] [Bug #11787]'

    s = EnvUtil.with_default_internal(::Encoding::EUC_JP) do
      [e("\xB4\xC1\xBB\xFA")].inspect
    end
    assert_equal(e("[\"\xB4\xC1\xBB\xFA\"]"), s, bug11787)
  end

  def test_greek_capital_gap
    bug12204 = '[ruby-core:74478] [Bug #12204] GREEK CAPITAL RHO and SIGMA'
    assert_equal("\u03A3", "\u03A1".succ, bug12204)
  end
end
