# frozen_string_literal: false
require 'test/unit'

class TestSprintf < Test::Unit::TestCase
  def test_positional
    assert_equal("     00001", sprintf("%*1$.*2$3$d", 10, 5, 1))
  end

  def test_binary
    assert_equal("0", sprintf("%b", 0))
    assert_equal("1", sprintf("%b", 1))
    assert_equal("10", sprintf("%b", 2))
    assert_equal("..1", sprintf("%b", -1))

    assert_equal("   0", sprintf("%4b", 0))
    assert_equal("   1", sprintf("%4b", 1))
    assert_equal("  10", sprintf("%4b", 2))
    assert_equal(" ..1", sprintf("%4b", -1))

    assert_equal("0000", sprintf("%04b", 0))
    assert_equal("0001", sprintf("%04b", 1))
    assert_equal("0010", sprintf("%04b", 2))
    assert_equal("..11", sprintf("%04b", -1))

    assert_equal("0000", sprintf("%.4b", 0))
    assert_equal("0001", sprintf("%.4b", 1))
    assert_equal("0010", sprintf("%.4b", 2))
    assert_equal("..11", sprintf("%.4b", -1))

    assert_equal("  0000", sprintf("%6.4b", 0))
    assert_equal("  0001", sprintf("%6.4b", 1))
    assert_equal("  0010", sprintf("%6.4b", 2))
    assert_equal("  ..11", sprintf("%6.4b", -1))

    assert_equal("   0", sprintf("%#4b", 0))
    assert_equal(" 0b1", sprintf("%#4b", 1))
    assert_equal("0b10", sprintf("%#4b", 2))
    assert_equal("0b..1", sprintf("%#4b", -1))

    assert_equal("0000", sprintf("%#04b", 0))
    assert_equal("0b01", sprintf("%#04b", 1))
    assert_equal("0b10", sprintf("%#04b", 2))
    assert_equal("0b..1", sprintf("%#04b", -1))

    assert_equal("0000", sprintf("%#.4b", 0))
    assert_equal("0b0001", sprintf("%#.4b", 1))
    assert_equal("0b0010", sprintf("%#.4b", 2))
    assert_equal("0b..11", sprintf("%#.4b", -1))

    assert_equal("  0000", sprintf("%#6.4b", 0))
    assert_equal("0b0001", sprintf("%#6.4b", 1))
    assert_equal("0b0010", sprintf("%#6.4b", 2))
    assert_equal("0b..11", sprintf("%#6.4b", -1))

    assert_equal("+0", sprintf("%+b", 0))
    assert_equal("+1", sprintf("%+b", 1))
    assert_equal("+10", sprintf("%+b", 2))
    assert_equal("-1", sprintf("%+b", -1))

    assert_equal("  +0", sprintf("%+4b", 0))
    assert_equal("  +1", sprintf("%+4b", 1))
    assert_equal(" +10", sprintf("%+4b", 2))
    assert_equal("  -1", sprintf("%+4b", -1))

    assert_equal("+000", sprintf("%+04b", 0))
    assert_equal("+001", sprintf("%+04b", 1))
    assert_equal("+010", sprintf("%+04b", 2))
    assert_equal("-001", sprintf("%+04b", -1))

    assert_equal("+0000", sprintf("%+.4b", 0))
    assert_equal("+0001", sprintf("%+.4b", 1))
    assert_equal("+0010", sprintf("%+.4b", 2))
    assert_equal("-0001", sprintf("%+.4b", -1))

    assert_equal(" +0000", sprintf("%+6.4b", 0))
    assert_equal(" +0001", sprintf("%+6.4b", 1))
    assert_equal(" +0010", sprintf("%+6.4b", 2))
    assert_equal(" -0001", sprintf("%+6.4b", -1))
  end

  def test_nan
    nan = 0.0 / 0.0
    assert_equal("NaN", sprintf("%f", nan))
    assert_equal("NaN", sprintf("%-f", nan))
    assert_equal("+NaN", sprintf("%+f", nan))

    assert_equal("     NaN", sprintf("%8f", nan))
    assert_equal("NaN     ", sprintf("%-8f", nan))
    assert_equal("    +NaN", sprintf("%+8f", nan))

    assert_equal("     NaN", sprintf("%08f", nan))
    assert_equal("NaN     ", sprintf("%-08f", nan))
    assert_equal("    +NaN", sprintf("%+08f", nan))

    assert_equal("     NaN", sprintf("% 8f", nan))
    assert_equal(" NaN    ", sprintf("%- 8f", nan))
    assert_equal("    +NaN", sprintf("%+ 8f", nan))

    assert_equal("     NaN", sprintf("% 08f", nan))
    assert_equal(" NaN    ", sprintf("%- 08f", nan))
    assert_equal("    +NaN", sprintf("%+ 08f", nan))
  end

  def test_inf
    inf = 1.0 / 0.0
    assert_equal("Inf", sprintf("%f", inf))
    assert_equal("Inf", sprintf("%-f", inf))
    assert_equal("+Inf", sprintf("%+f", inf))

    assert_equal("     Inf", sprintf("%8f", inf))
    assert_equal("Inf     ", sprintf("%-8f", inf))
    assert_equal("    +Inf", sprintf("%+8f", inf))

    assert_equal("     Inf", sprintf("%08f", inf))
    assert_equal("Inf     ", sprintf("%-08f", inf))
    assert_equal("    +Inf", sprintf("%+08f", inf))

    assert_equal("     Inf", sprintf("% 8f", inf))
    assert_equal(" Inf    ", sprintf("%- 8f", inf))
    assert_equal("    +Inf", sprintf("%+ 8f", inf))

    assert_equal("     Inf", sprintf("% 08f", inf))
    assert_equal(" Inf    ", sprintf("%- 08f", inf))
    assert_equal("    +Inf", sprintf("%+ 08f", inf))

    assert_equal("-Inf", sprintf("%f", -inf))
    assert_equal("-Inf", sprintf("%-f", -inf))
    assert_equal("-Inf", sprintf("%+f", -inf))

    assert_equal("    -Inf", sprintf("%8f", -inf))
    assert_equal("-Inf    ", sprintf("%-8f", -inf))
    assert_equal("    -Inf", sprintf("%+8f", -inf))

    assert_equal("    -Inf", sprintf("%08f", -inf))
    assert_equal("-Inf    ", sprintf("%-08f", -inf))
    assert_equal("    -Inf", sprintf("%+08f", -inf))

    assert_equal("    -Inf", sprintf("% 8f", -inf))
    assert_equal("-Inf    ", sprintf("%- 8f", -inf))
    assert_equal("    -Inf", sprintf("%+ 8f", -inf))

    assert_equal("    -Inf", sprintf("% 08f", -inf))
    assert_equal("-Inf    ", sprintf("%- 08f", -inf))
    assert_equal("    -Inf", sprintf("%+ 08f", -inf))
    assert_equal('..f00000000',
      sprintf("%x", -2**32), '[ruby-dev:32351]')
    assert_equal("..101111111111111111111111111111111",
      sprintf("%b", -2147483649), '[ruby-dev:32365]')
    assert_equal(" Inf", sprintf("% e", inf), '[ruby-dev:34002]')
  end

  def test_bignum
    assert_match(/\A10{120}\.0+\z/, sprintf("%f", 100**60))
    assert_match(/\A10{180}\.0+\z/, sprintf("%f", 1000**60))
  end

  def test_rational
    assert_match(/\A0\.10+\z/, sprintf("%.60f", 0.1r))
    assert_match(/\A0\.010+\z/, sprintf("%.60f", 0.01r))
    assert_match(/\A0\.0010+\z/, sprintf("%.60f", 0.001r))
    assert_match(/\A0\.3+\z/, sprintf("%.60f", 1/3r))
    assert_match(/\A1\.20+\z/, sprintf("%.60f", 1.2r))

    ["", *"0".."9"].each do |len|
      ["", *".0"..".9"].each do |prec|
        ['', '+', '-', ' ', '0', '+0', '-0', ' 0', '+ ', '- ', '+ 0', '- 0'].each do |flags|
          fmt = "%#{flags}#{len}#{prec}f"
          [0, 0.1, 0.01, 0.001, 1.001, 100.0, 100.001, 10000000000.0, 0.00000000001, 1/3r, 2/3r, 1.2r, 10r].each do |num|
            assert_equal(sprintf(fmt, num.to_f), sprintf(fmt, num.to_r), "sprintf(#{fmt.inspect}, #{num.inspect}.to_r)")
            assert_equal(sprintf(fmt, -num.to_f), sprintf(fmt, -num.to_r), "sprintf(#{fmt.inspect}, #{(-num).inspect}.to_r)") if num > 0
          end
        end
      end
    end

    bug11766 = '[ruby-core:71806] [Bug #11766]'
    assert_equal("x"*10+"     1.0", sprintf("x"*10+"%8.1f", 1r), bug11766)
  end

  def test_rational_precision
    assert_match(/\A0\.\d{600}\z/, sprintf("%.600f", 600**~60))
  end

  def test_hash
    options = {:capture=>/\d+/}
    assert_equal("with options {:capture=>/\\d+/}", sprintf("with options %p" % options))
  end

  def test_invalid
    # Star precision before star width:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.**d", 5, 10, 1)}

    # Precision before flags and width:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.5+05d", 5)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.5 5d", 5)}

    # Overriding a star width with a numeric one:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%*1s", 5, 1)}

    # Width before flags:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%5+0d", 1)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%5 0d", 1)}

    # Specifying width multiple times:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%50+30+20+10+5d", 5)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%50 30 20 10 5d", 5)}

    # Specifying the precision multiple times with negative star arguments:
    assert_raise(ArgumentError, "[ruby-core:11570]") {sprintf("%.*.*.*.*f", -1, -1, -1, 5, 1)}

    # Null bytes after percent signs are removed:
    assert_equal("%\0x hello", sprintf("%\0x hello"), "[ruby-core:11571]")

    assert_raise(ArgumentError, "[ruby-core:11573]") {sprintf("%.25555555555555555555555555555555555555s", "hello")}

    assert_raise(ArgumentError) { sprintf("%\1", 1) }
    assert_raise(ArgumentError) { sprintf("%!", 1) }
    assert_raise(ArgumentError) { sprintf("%1$1$d", 1) }
    assert_raise(ArgumentError) { sprintf("%0%") }

    assert_raise_with_message(ArgumentError, /unnumbered\(1\) mixed with numbered/) { sprintf("%1$*d", 3) }
    assert_raise_with_message(ArgumentError, /unnumbered\(1\) mixed with numbered/) { sprintf("%1$.*d", 3) }

    verbose, $VERBOSE = $VERBOSE, nil
    assert_nothing_raised { sprintf("", 1) }
  ensure
    $VERBOSE = verbose
  end

  def test_float
    assert_equal("36893488147419111424",
                 sprintf("%20.0f", 36893488147419107329.0))
    assert_equal(" Inf", sprintf("% 0e", 1.0/0.0), "moved from btest/knownbug")
    assert_equal("       -0.", sprintf("%#10.0f", -0.5), "[ruby-dev:42552]")
    # out of spec
    #assert_equal("0x1p+2",   sprintf('%.0a', Float('0x1.fp+1')),   "[ruby-dev:42551]")
    #assert_equal("-0x1.0p+2", sprintf('%.1a', Float('-0x1.ffp+1')), "[ruby-dev:42551]")
  end

  def test_float_hex
    assert_equal("-0x0p+0", sprintf("%a", -0.0))
    assert_equal("0x0p+0", sprintf("%a", 0.0))
    assert_equal("0x1p-1", sprintf("%a", 0.5))
    assert_equal("0x1p+0", sprintf("%a", 1.0))
    assert_equal("0x1p+1", sprintf("%a", 2.0))
    assert_equal("0x1p+10", sprintf("%a", 1024))
    assert_equal("0x1.23456p+789", sprintf("%a", 3.704450999893983e+237))
    assert_equal("0x1p-1074", sprintf("%a", 4.9e-324))
    assert_equal("Inf", sprintf("%e", Float::INFINITY))
    assert_equal("Inf", sprintf("%E", Float::INFINITY))
    assert_equal("NaN", sprintf("%e", Float::NAN))
    assert_equal("NaN", sprintf("%E", Float::NAN))

    assert_equal("   -0x1p+0", sprintf("%10a", -1))
    assert_equal(" -0x1.8p+0", sprintf("%10a", -1.5))
    assert_equal(" -0x1.4p+0", sprintf("%10a", -1.25))
    assert_equal(" -0x1.2p+0", sprintf("%10a", -1.125))
    assert_equal(" -0x1.1p+0", sprintf("%10a", -1.0625))
    assert_equal("-0x1.08p+0", sprintf("%10a", -1.03125))

    bug3962 = '[ruby-core:32841]'
    assert_equal("-0x0001p+0", sprintf("%010a", -1), bug3962)
    assert_equal("-0x01.8p+0", sprintf("%010a", -1.5), bug3962)
    assert_equal("-0x01.4p+0", sprintf("%010a", -1.25), bug3962)
    assert_equal("-0x01.2p+0", sprintf("%010a", -1.125), bug3962)
    assert_equal("-0x01.1p+0", sprintf("%010a", -1.0625), bug3962)
    assert_equal("-0x1.08p+0", sprintf("%010a", -1.03125), bug3962)

    bug3964 = '[ruby-core:32848]'
    assert_equal("0x000000000000000p+0", sprintf("%020a",  0), bug3964)
    assert_equal("0x000000000000001p+0", sprintf("%020a", 1), bug3964)
    assert_equal("-0x00000000000001p+0", sprintf("%020a", -1), bug3964)
    assert_equal("0x00000000000000.p+0", sprintf("%#020a",  0), bug3964)

    bug3965 = '[ruby-dev:42431]'
    assert_equal("0x1.p+0", sprintf("%#.0a",  1), bug3965)
    assert_equal("0x00000000000000.p+0", sprintf("%#020a",  0), bug3965)
    assert_equal("0x0000.0000000000p+0", sprintf("%#020.10a",  0), bug3965)

    bug3979 = '[ruby-dev:42453]'
    assert_equal("          0x0.000p+0", sprintf("%20.3a",  0), bug3979)
    assert_equal("          0x1.000p+0", sprintf("%20.3a",  1), bug3979)
  end

  def test_float_prec
    assert_equal("5.00", sprintf("%.2f",5.005))
    assert_equal("5.02", sprintf("%.2f",5.015))
    assert_equal("5.02", sprintf("%.2f",5.025))
    assert_equal("5.04", sprintf("%.2f",5.035))
    bug12889 = '[ruby-core:77864] [Bug #12889]'
    assert_equal("1234567892", sprintf("%.0f", 1234567891.99999))
    assert_equal("1234567892", sprintf("%.0f", 1234567892.49999))
    assert_equal("1234567892", sprintf("%.0f", 1234567892.50000))
    assert_equal("1234567894", sprintf("%.0f", 1234567893.50000))
    assert_equal("1234567892", sprintf("%.0f", 1234567892.00000), bug12889)
  end

  BSIZ = 120

  def test_skip
    assert_equal(" " * BSIZ + "1", sprintf(" " * BSIZ + "%d", 1))
  end

  def test_char
    assert_equal("a", sprintf("%c", 97))
    assert_equal("a", sprintf("%c", ?a))
    assert_raise(ArgumentError) { sprintf("%c", sprintf("%c%c", ?a, ?a)) }
    assert_equal(" " * (BSIZ - 1) + "a", sprintf(" " * (BSIZ - 1) + "%c", ?a))
    assert_equal(" " * (BSIZ - 1) + "a", sprintf(" " * (BSIZ - 1) + "%-1c", ?a))
    assert_equal(" " * BSIZ + "a", sprintf("%#{ BSIZ + 1 }c", ?a))
    assert_equal("a" + " " * BSIZ, sprintf("%-#{ BSIZ + 1 }c", ?a))
  end

  def test_string
    assert_equal("foo", sprintf("%s", "foo"))
    assert_equal("fo", sprintf("%.2s", "foo"))
    assert_equal(" " * BSIZ, sprintf("%s", " " * BSIZ))
    assert_equal(" " * (BSIZ - 1) + "foo", sprintf("%#{ BSIZ - 1 + 3 }s", "foo"))
    assert_equal(" " * BSIZ + "foo", sprintf("%#{ BSIZ + 3 }s", "foo"))
    assert_equal("foo" + " " * BSIZ, sprintf("%-#{ BSIZ + 3 }s", "foo"))
  end

  def test_integer
    assert_equal("01", sprintf("%#o", 1))
    assert_equal("0x1", sprintf("%#x", 1))
    assert_equal("0X1", sprintf("%#X", 1))
    assert_equal("0b1", sprintf("%#b", 1))
    assert_equal("0B1", sprintf("%#B", 1))
    assert_equal("1", sprintf("%d", 1.0))
    assert_equal("4294967296", sprintf("%d", (2**32).to_f))
    assert_equal("-2147483648", sprintf("%d", -(2**31).to_f))
    assert_equal("18446744073709551616", sprintf("%d", (2**64).to_f))
    assert_equal("-9223372036854775808", sprintf("%d", -(2**63).to_f))
    assert_equal("1", sprintf("%d", "1"))
    o = Object.new; def o.to_int; 1; end
    assert_equal("1", sprintf("%d", o))
    assert_equal("+1", sprintf("%+d", 1))
    assert_equal(" 1", sprintf("% d", 1))
    assert_equal("..f", sprintf("%x", -1))
    assert_equal("..7", sprintf("%o", -1))
    one = (2**32).coerce(1).first
    mone = (2**32).coerce(-1).first
    assert_equal("+1", sprintf("%+d", one))
    assert_equal(" 1", sprintf("% d", one))
    assert_equal("..f", sprintf("%x", mone))
    assert_equal("..7", sprintf("%o", mone))
    assert_equal(" " * BSIZ + "1", sprintf("%#{ BSIZ + 1 }d", one))
    assert_equal(" " * (BSIZ - 1) + "1", sprintf(" " * (BSIZ - 1) + "%d", 1))
  end

  def test_float2
    inf = 1.0 / 0.0
    assert_equal(" " * BSIZ + "Inf", sprintf("%#{ BSIZ + 3 }.1f", inf))
    assert_equal("+Inf", sprintf("%+-f", inf))
    assert_equal(" " * BSIZ + "1.0", sprintf("%#{ BSIZ + 3 }.1f", 1.0))
  end

  class T012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
  end

  def test_star
    assert_equal("-1 ", sprintf("%*d", -3, -1))
    assert_raise_with_message(ArgumentError, /width too big/) {
      sprintf("%*999999999999999999999999999999999999999999999999999999999999$d", 1)
    }
    assert_raise_with_message(ArgumentError, /prec too big/) {
      sprintf("%.*999999999999999999999999999999999999999999999999999999999999$d", 1)
    }
  end

  def test_escape
    assert_equal("%" * BSIZ, sprintf("%%" * BSIZ))
  end

  def test_rb_sprintf
    assert_match(/^#<TestSprintf::T012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789:0x[0-9a-f]+>$/,
                 T012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789.new.inspect)
  end

  def test_negative_hex
    s1 = sprintf("%0x", -0x40000000)
    s2 = sprintf("%0x", -0x40000001)
    b1 = (/\.\./ =~ s1) != nil
    b2 = (/\.\./ =~ s2) != nil
    assert_equal(b1, b2, "[ruby-dev:33224]")
  end

  def test_named_untyped
    assert_equal("value", sprintf("%<key>s", :key => "value"))
    assert_raise_with_message(ArgumentError, "named<key2> after numbered") {sprintf("%1$<key2>s", :key => "value")}
    assert_raise_with_message(ArgumentError, "named<key2> after unnumbered(2)") {sprintf("%s%s%<key2>s", "foo", "bar", :key => "value")}
    assert_raise_with_message(ArgumentError, "named<key2> after <key>") {sprintf("%<key><key2>s", :key => "value")}
    assert_raise_with_message(KeyError, "key<key> not found") {sprintf("%<key>s", {})}
  end

  def test_named_untyped_enc
    key = "\u{3012}"
    [Encoding::UTF_8, Encoding::EUC_JP].each do |enc|
      k = key.encode(enc)
      e = assert_raise_with_message(ArgumentError, "named<#{k}> after numbered") {sprintf("%1$<#{k}>s", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named<#{k}> after unnumbered(2)") {sprintf("%s%s%<#{k}>s", "foo", "bar", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named<#{k}> after <key>") {sprintf("%<key><#{k}>s", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named<key> after <#{k}>") {sprintf("%<#{k}><key>s", k.to_sym => "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(KeyError, "key<#{k}> not found") {sprintf("%<#{k}>s", {})}
      assert_equal(enc, e.message.encoding)
    end
  end

  def test_named_typed
    assert_equal("value", sprintf("%{key}", :key => "value"))
    assert_raise_with_message(ArgumentError, "named{key2} after numbered") {sprintf("%1${key2}", :key => "value")}
    assert_raise_with_message(ArgumentError, "named{key2} after unnumbered(2)") {sprintf("%s%s%{key2}", "foo", "bar", :key => "value")}
    assert_raise_with_message(ArgumentError, "named{key2} after <key>") {sprintf("%<key>{key2}", :key => "value")}
    assert_equal("value{key2}", sprintf("%{key}{key2}", :key => "value"))
    assert_raise_with_message(KeyError, "key{key} not found") {sprintf("%{key}", {})}
  end

  def test_named_typed_enc
    key = "\u{3012}"
    [Encoding::UTF_8, Encoding::EUC_JP].each do |enc|
      k = key.encode(enc)
      e = assert_raise_with_message(ArgumentError, "named{#{k}} after numbered") {sprintf("%1${#{k}}s", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named{#{k}} after unnumbered(2)") {sprintf("%s%s%{#{k}}s", "foo", "bar", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named{#{k}} after <key>") {sprintf("%<key>{#{k}}s", key: "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(ArgumentError, "named{key} after <#{k}>") {sprintf("%<#{k}>{key}s", k.to_sym => "value")}
      assert_equal(enc, e.message.encoding)
      e = assert_raise_with_message(KeyError, "key{#{k}} not found") {sprintf("%{#{k}}", {})}
      assert_equal(enc, e.message.encoding)
    end
  end

  def test_named_default
    h = Hash.new('world')
    assert_equal("hello world", "hello %{location}" % h)
    assert_equal("hello world", "hello %<location>s" % h)
  end

  def test_named_with_nil
    h = { key: nil, key2: "key2_val" }
    assert_equal("key is , key2 is key2_val", "key is %{key}, key2 is %{key2}" % h)
  end

  def test_width_underflow
    bug = 'https://github.com/mruby/mruby/issues/3347'
    assert_equal("!", sprintf("%*c", 0, ?!.ord), bug)
  end
end
