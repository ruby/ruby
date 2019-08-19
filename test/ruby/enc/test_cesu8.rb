# frozen_string_literal: false
require 'test/unit'

class TestCESU8 < Test::Unit::TestCase

  def encdump(obj)
    case obj
    when String
      obj.dump
    when Regexp
      "Regexp.new(#{encdump(obj.source)}, #{obj.options})"
    else
      raise Argument, "unexpected: #{obj.inspect}"
    end
  end

  def enccall(recv, meth, *args)
    desc = ''
    if String === recv
      desc << encdump(recv)
    else
      desc << recv.inspect
    end
    desc << '.' << meth.to_s
    if !args.empty?
      desc << '('
      args.each_with_index {|a, i|
        desc << ',' if 0 < i
        if String === a
          desc << encdump(a)
        else
          desc << a.inspect
        end
      }
      desc << ')'
    end
    result = nil
    assert_nothing_raised(desc) {
      result = recv.send(meth, *args)
    }
    result
  end

  def assert_str_equal(expected, actual, message=nil)
    full_message = build_message(message, <<EOT)
#{encdump expected} expected but not equal to
#{encdump actual}.
EOT
    assert_equal(expected, actual, full_message)
  end

  # tests start

  def test_cesu8_valid_encoding
    all_assertions do |a|
      [
        "\x00",
        "\x7f",
        "\u0080",
        "\u07ff",
        "\u0800",
        "\ud7ff",
        "\xed\xa0\x80\xed\xb0\x80",
        "\xed\xaf\xbf\xed\xbf\xbf",
        "\ue000",
        "\uffff",
      ].each {|s|
        s.force_encoding("cesu-8")
        a.for(s) {
          assert_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
      [
        "\x80",
        "\xc0\x80",
        "\xc0",
        "\xe0\x80\x80",
        "\xed\xa0\x80",
        "\xed\xb0\x80\xed\xb0\x80",
        "\xe0",
        "\xff",
      ].each {|s|
        s.force_encoding("cesu-8")
        a.for(s) {
          assert_not_predicate(s, :valid_encoding?, "#{encdump s}.valid_encoding?")
        }
      }
    end
  end

  def test_cesu8_ord
    [
      ["\x00", 0],
      ["\x7f", 0x7f],
      ["\u0080", 0x80],
      ["\u07ff", 0x7ff],
      ["\u0800", 0x800],
      ["\ud7ff", 0xd7ff],
      ["\xed\xa0\x80\xed\xb0\x80", 0x10000],
      ["\xed\xaf\xbf\xed\xbf\xbf", 0x10ffff],
      ["\xee\x80\x80", 0xe000],
      ["\xef\xbf\xbf", 0xffff],
    ].each do |chr, ord|
      chr.force_encoding("cesu-8")
      assert_equal ord, chr.ord
      assert_equal chr, ord.chr("cesu-8")
    end
  end
end
