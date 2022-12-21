# -*- coding: utf-8 -*-
# frozen_string_literal: true
#
# test/strscan/test_stringscanner.rb
#

require 'strscan'
require 'test/unit'

class TestStringScanner < Test::Unit::TestCase
  def create_string_scanner(string, *args)
    StringScanner.new(string, *args)
  end

  def test_s_new
    s = create_string_scanner('test string')
    assert_instance_of StringScanner, s
    assert_equal false, s.eos?

    str = 'test string'.dup
    s = create_string_scanner(str, false)
    assert_instance_of StringScanner, s
    assert_equal false, s.eos?
    assert_same str, s.string
  end

  UNINIT_ERROR = ArgumentError

  def test_s_allocate
    s = StringScanner.allocate
    assert_equal '#<StringScanner (uninitialized)>', s.inspect.sub(/StringScanner_C/, 'StringScanner')
    assert_raise(UNINIT_ERROR) { s.eos? }
    assert_raise(UNINIT_ERROR) { s.scan(/a/) }
    s.string = 'test'
    assert_equal '#<StringScanner 0/4 @ "test">', s.inspect.sub(/StringScanner_C/, 'StringScanner')
    assert_nothing_raised(UNINIT_ERROR) { s.eos? }
    assert_equal false, s.eos?
  end

  def test_s_mustc
    assert_nothing_raised(NotImplementedError) {
        StringScanner.must_C_version
    }
  end

  def test_dup
    s = create_string_scanner('test string')
    d = s.dup
    assert_equal s.inspect, d.inspect
    assert_equal s.string, d.string
    assert_equal s.pos, d.pos
    assert_equal s.matched?, d.matched?
    assert_equal s.eos?, d.eos?

    s = create_string_scanner('test string')
    s.scan(/test/)
    d = s.dup
    assert_equal s.inspect, d.inspect
    assert_equal s.string, d.string
    assert_equal s.pos, d.pos
    assert_equal s.matched?, d.matched?
    assert_equal s.eos?, d.eos?

    s = create_string_scanner('test string')
    s.scan(/test/)
    s.scan(/NOT MATCH/)
    d = s.dup
    assert_equal s.inspect, d.inspect
    assert_equal s.string, d.string
    assert_equal s.pos, d.pos
    assert_equal s.matched?, d.matched?
    assert_equal s.eos?, d.eos?

    s = create_string_scanner('test string')
    s.terminate
    d = s.dup
    assert_equal s.inspect, d.inspect
    assert_equal s.string, d.string
    assert_equal s.pos, d.pos
    assert_equal s.matched?, d.matched?
    assert_equal s.eos?, d.eos?
  end

  def test_const_Version
    assert_instance_of String, StringScanner::Version
    assert_equal true, StringScanner::Version.frozen?
  end

  def test_const_Id
    assert_instance_of String, StringScanner::Id
    assert_equal true, StringScanner::Id.frozen?
  end

  def test_inspect
    str = 'test string'.dup
    s = create_string_scanner(str, false)
    assert_instance_of String, s.inspect
    assert_equal s.inspect, s.inspect
    assert_equal '#<StringScanner 0/11 @ "test ...">', s.inspect.sub(/StringScanner_C/, 'StringScanner')
    s.get_byte
    assert_equal '#<StringScanner 1/11 "t" @ "est s...">', s.inspect.sub(/StringScanner_C/, 'StringScanner')

    s = create_string_scanner("\n")
    assert_equal '#<StringScanner 0/1 @ "\n">', s.inspect
  end

  def test_eos?
    s = create_string_scanner('test string')
    assert_equal false, s.eos?
    assert_equal false, s.eos?
    s.scan(/\w+/)
    assert_equal false, s.eos?
    assert_equal false, s.eos?
    s.scan(/\s+/)
    s.scan(/\w+/)
    assert_equal true, s.eos?
    assert_equal true, s.eos?
    s.scan(/\w+/)
    assert_equal true, s.eos?

    s = create_string_scanner('test'.dup)
    s.scan(/te/)
    s.string.replace ''
    assert_equal true, s.eos?
  end

  def test_bol?
    s = create_string_scanner("a\nbbb\n\ncccc\nddd\r\neee")
    assert_equal true, s.bol?
    assert_equal true, s.bol?
    s.scan(/a/)
    assert_equal false, s.bol?
    assert_equal false, s.bol?
    s.scan(/\n/)
    assert_equal true, s.bol?
    s.scan(/b/)
    assert_equal false, s.bol?
    s.scan(/b/)
    assert_equal false, s.bol?
    s.scan(/b/)
    assert_equal false, s.bol?
    s.scan(/\n/)
    assert_equal true, s.bol?
    s.unscan
    assert_equal false, s.bol?
    s.scan(/\n/)
    s.scan(/\n/)
    assert_equal true, s.bol?
    s.scan(/c+\n/)
    assert_equal true, s.bol?
    s.scan(/d+\r\n/)
    assert_equal true, s.bol?
    s.scan(/e+/)
    assert_equal false, s.bol?
  end

  def test_string
    s = create_string_scanner('test')
    assert_equal 'test', s.string
    s.string = 'a'
    assert_equal 'a', s.string
    s.scan(/a/)
    s.string = 'b'
    assert_equal 0, s.pos
  end

  def test_string_set_is_equal
    name = 'tenderlove'

    s = create_string_scanner(name)
    assert_equal name.object_id, s.string.object_id

    s.string = name
    assert_equal name.object_id, s.string.object_id
  end

  def test_string_append
    s = create_string_scanner('tender'.dup)
    s << 'love'
    assert_equal 'tenderlove', s.string

    s.string = 'tender'.dup
    s << 'love'
    assert_equal 'tenderlove', s.string
  end

  def test_pos
    s = create_string_scanner('test string')
    assert_equal 0, s.pos
    s.get_byte
    assert_equal 1, s.pos
    s.get_byte
    assert_equal 2, s.pos
    s.terminate
    assert_equal 11, s.pos
  end

  def test_pos_unicode
    s = create_string_scanner("abcädeföghi")
    assert_equal 0, s.charpos
    assert_equal "abcä", s.scan_until(/ä/)
    assert_equal 4, s.charpos
    assert_equal "defö", s.scan_until(/ö/)
    assert_equal 8, s.charpos
    s.terminate
    assert_equal 11, s.charpos
  end

  def test_charpos_not_use_string_methods
    omit "not supported on TruffleRuby" if RUBY_ENGINE == "truffleruby"

    string = +'abcädeföghi'
    scanner = create_string_scanner(string)

    class << string
      EnvUtil.suppress_warning do
        undef_method(*instance_methods)
      end
    end

    assert_equal 0, scanner.charpos
    assert_equal "abcä", scanner.scan_until(/ä/)
    assert_equal 4, scanner.charpos
    assert_equal "defö", scanner.scan_until(/ö/)
    assert_equal 8, scanner.charpos
  end

  def test_concat
    s = create_string_scanner('a'.dup)
    s.scan(/a/)
    s.concat 'b'
    assert_equal false, s.eos?
    assert_equal 'b', s.scan(/b/)
    assert_equal true, s.eos?
    s.concat 'c'
    assert_equal false, s.eos?
    assert_equal 'c', s.scan(/c/)
    assert_equal true, s.eos?
  end

  def test_scan
    s = create_string_scanner('stra strb strc', true)
    tmp = s.scan(/\w+/)
    assert_equal 'stra', tmp

    tmp = s.scan(/\s+/)
    assert_equal ' ', tmp

    assert_equal 'strb', s.scan(/\w+/)
    assert_equal ' ',    s.scan(/\s+/)

    tmp = s.scan(/\w+/)
    assert_equal 'strc', tmp

    assert_nil           s.scan(/\w+/)
    assert_nil           s.scan(/\w+/)


    str = 'stra strb strc'.dup
    s = create_string_scanner(str, false)
    tmp = s.scan(/\w+/)
    assert_equal 'stra', tmp

    tmp = s.scan(/\s+/)
    assert_equal ' ', tmp

    assert_equal 'strb', s.scan(/\w+/)
    assert_equal ' ',    s.scan(/\s+/)

    tmp = s.scan(/\w+/)
    assert_equal 'strc', tmp

    assert_nil           s.scan(/\w+/)
    assert_nil           s.scan(/\w+/)

    s = create_string_scanner('test'.dup)
    s.scan(/te/)
    # This assumes #string does not duplicate string,
    # but it is implementation specific issue.
    # DO NOT RELY ON THIS FEATURE.
    s.string.replace ''
    # unspecified: assert_equal 2, s.pos
    assert_equal nil, s.scan(/test/)

    # [ruby-bugs:4361]
    s = create_string_scanner("")
    assert_equal "", s.scan(//)
    assert_equal "", s.scan(//)
  end

  def test_scan_string
    s = create_string_scanner('stra strb strc')
    assert_equal 'str', s.scan('str')
    assert_equal 'str', s[0]
    assert_equal 3, s.pos
    assert_equal 'a ', s.scan('a ')

    str = 'stra strb strc'.dup
    s = create_string_scanner(str, false)
    matched = s.scan('str')
    assert_equal 'str', matched
  end

  def test_skip
    s = create_string_scanner('stra strb strc', true)
    assert_equal 4, s.skip(/\w+/)
    assert_equal 1, s.skip(/\s+/)
    assert_equal 4, s.skip(/\w+/)
    assert_equal 1, s.skip(/\s+/)
    assert_equal 4, s.skip(/\w+/)
    assert_nil      s.skip(/\w+/)
    assert_nil      s.skip(/\s+/)
    assert_equal true, s.eos?

    s = create_string_scanner('test'.dup)
    s.scan(/te/)
    s.string.replace ''
    assert_equal nil, s.skip(/./)

    # [ruby-bugs:4361]
    s = create_string_scanner("")
    assert_equal 0, s.skip(//)
    assert_equal 0, s.skip(//)
  end

  def test_skip_with_begenning_of_string_anchor_match
    s = create_string_scanner("a\nb")
    assert_equal 2, s.skip(/a\n/)
    assert_equal 1, s.skip(/\Ab/)
  end

  def test_skip_with_begenning_of_line_anchor_match
    s = create_string_scanner("a\nbc")
    assert_equal 2, s.skip(/a\n/)
    assert_equal 1, s.skip(/^b/)
    assert_equal 1, s.skip(/^c/)
  end

  def test_getch
    s = create_string_scanner('abcde')
    assert_equal 'a', s.getch
    assert_equal 'b', s.getch
    assert_equal 'c', s.getch
    assert_equal 'd', s.getch
    assert_equal 'e', s.getch
    assert_nil        s.getch

    s = create_string_scanner("\244\242".dup.force_encoding("euc-jp"))
    assert_equal "\244\242".dup.force_encoding("euc-jp"), s.getch
    assert_nil s.getch

    s = create_string_scanner('test'.dup)
    s.scan(/te/)
    s.string.replace ''
    assert_equal nil, s.getch
  end

  def test_get_byte
    s = create_string_scanner('abcde')
    assert_equal 'a', s.get_byte
    assert_equal 'b', s.get_byte
    assert_equal 'c', s.get_byte
    assert_equal 'd', s.get_byte
    assert_equal 'e', s.get_byte
    assert_nil        s.get_byte
    assert_nil        s.get_byte

    s = create_string_scanner("\244\242".dup.force_encoding("euc-jp"))
    assert_equal "\244".dup.force_encoding("euc-jp"), s.get_byte
    assert_equal "\242".dup.force_encoding("euc-jp"), s.get_byte
    assert_nil s.get_byte

    s = create_string_scanner('test'.dup)
    s.scan(/te/)
    s.string.replace ''
    assert_equal nil, s.get_byte
  end

  def test_matched
    s = create_string_scanner('stra strb strc')
    s.scan(/\w+/)
    assert_equal 'stra', s.matched
    s.scan(/\s+/)
    assert_equal ' ', s.matched
    s.scan('st')
    assert_equal 'st', s.matched
    s.scan(/\w+/)
    assert_equal 'rb', s.matched
    s.scan(/\s+/)
    assert_equal ' ', s.matched
    s.scan(/\w+/)
    assert_equal 'strc', s.matched
    s.scan(/\w+/)
    assert_nil s.matched
    s.getch
    assert_nil s.matched

    s = create_string_scanner('stra strb strc')
    s.getch
    assert_equal 's', s.matched
    s.get_byte
    assert_equal 't', s.matched
    assert_equal 't', s.matched
  end

  def test_AREF
    s = create_string_scanner('stra strb strc')

    s.scan(/\w+/)
    assert_nil           s[-2]
    assert_equal 'stra', s[-1]
    assert_equal 'stra', s[0]
    assert_nil           s[1]
    assert_raise(IndexError) { s[:c] }
    assert_raise(IndexError) { s['c'] }

    s.skip(/\s+/)
    assert_nil           s[-2]
    assert_equal ' ',    s[-1]
    assert_equal ' ',    s[0]
    assert_nil           s[1]

    s.scan(/(s)t(r)b/)
    assert_nil           s[-100]
    assert_nil           s[-4]
    assert_equal 'strb', s[-3]
    assert_equal 's',    s[-2]
    assert_equal 'r',    s[-1]
    assert_equal 'strb', s[0]
    assert_equal 's',    s[1]
    assert_equal 'r',    s[2]
    assert_nil           s[3]
    assert_nil           s[100]

    s.scan(/\s+/)

    s.getch
    assert_nil           s[-2]
    assert_equal 's',    s[-1]
    assert_equal 's',    s[0]
    assert_nil           s[1]

    s.get_byte
    assert_nil           s[-2]
    assert_equal 't',    s[-1]
    assert_equal 't',    s[0]
    assert_nil           s[1]

    s.scan(/.*/)
    s.scan(/./)
    assert_nil           s[0]
    assert_nil           s[0]


    s = create_string_scanner("\244\242".dup.force_encoding("euc-jp"))
    s.getch
    assert_equal "\244\242".dup.force_encoding("euc-jp"), s[0]

    s = create_string_scanner("foo bar baz")
    s.scan(/(?<a>\w+) (?<b>\w+) (\w+)/)
    assert_equal 'foo', s[1]
    assert_equal 'bar', s[2]
    assert_nil s[3]
    assert_equal 'foo', s[:a]
    assert_equal 'bar', s[:b]
    assert_raise(IndexError) { s[:c] }
    assert_equal 'foo', s['a']
    assert_equal 'bar', s['b']
    assert_raise(IndexError) { s['c'] }
    assert_raise_with_message(IndexError, /\u{30c6 30b9 30c8}/) { s["\u{30c6 30b9 30c8}"] }
  end

  def test_pre_match
    s = create_string_scanner('a b c d e')
    s.scan(/\w/)
    assert_equal '', s.pre_match
    s.skip(/\s/)
    assert_equal 'a', s.pre_match
    s.scan('b')
    assert_equal 'a ', s.pre_match
    s.scan_until(/c/)
    assert_equal 'a b ', s.pre_match
    s.getch
    assert_equal 'a b c', s.pre_match
    s.get_byte
    assert_equal 'a b c ', s.pre_match
    s.get_byte
    assert_equal 'a b c d', s.pre_match
    s.scan(/never match/)
    assert_nil s.pre_match
  end

  def test_post_match
    s = create_string_scanner('a b c d e')
    s.scan(/\w/)
    assert_equal ' b c d e', s.post_match
    s.skip(/\s/)
    assert_equal 'b c d e', s.post_match
    s.scan('b')
    assert_equal ' c d e', s.post_match
    s.scan_until(/c/)
    assert_equal ' d e', s.post_match
    s.getch
    assert_equal 'd e', s.post_match
    s.get_byte
    assert_equal ' e', s.post_match
    s.get_byte
    assert_equal 'e', s.post_match
    s.scan(/never match/)
    assert_nil s.post_match
    s.scan(/./)
    assert_equal '', s.post_match
    s.scan(/./)
    assert_nil s.post_match
  end

  def test_terminate
    s = create_string_scanner('ssss')
    s.getch
    s.terminate
    assert_equal true, s.eos?
    s.terminate
    assert_equal true, s.eos?
  end

  def test_reset
    s = create_string_scanner('ssss')
    s.getch
    s.reset
    assert_equal 0, s.pos
    s.scan(/\w+/)
    s.reset
    assert_equal 0, s.pos
    s.reset
    assert_equal 0, s.pos
  end

  def test_matched_size
    s = create_string_scanner('test string')
    assert_nil s.matched_size
    s.scan(/test/)
    assert_equal 4, s.matched_size
    assert_equal 4, s.matched_size
    s.scan(//)
    assert_equal 0, s.matched_size
    s.scan(/x/)
    assert_nil s.matched_size
    assert_nil s.matched_size
    s.terminate
    assert_nil s.matched_size

    s = create_string_scanner('test string')
    assert_nil s.matched_size
    s.scan(/test/)
    assert_equal 4, s.matched_size
    s.terminate
    assert_nil s.matched_size
  end

  def test_encoding
    ss = create_string_scanner("\xA1\xA2".dup.force_encoding("euc-jp"))
    assert_equal(Encoding::EUC_JP, ss.scan(/./e).encoding)
  end

  def test_encoding_string
    str = "\xA1\xA2".dup.force_encoding("euc-jp")
    ss = create_string_scanner(str)
    assert_equal(str.dup, ss.scan(str.dup))
  end

  def test_invalid_encoding_string
    omit "no encoding check on TruffleRuby for scan(String)" if RUBY_ENGINE == "truffleruby"

    str = "\xA1\xA2".dup.force_encoding("euc-jp")
    ss = create_string_scanner(str)
    assert_raise(Encoding::CompatibilityError) do
      ss.scan(str.encode("UTF-8"))
    end
  end

  def test_generic_regexp
    ss = create_string_scanner("\xA1\xA2".dup.force_encoding("euc-jp"))
    t = ss.scan(/./)
    assert_equal("\xa1\xa2".dup.force_encoding("euc-jp"), t)
  end

  def test_set_pos
    s = create_string_scanner("test string")
    s.pos = 7
    assert_equal("ring", s.rest)
  end

  def test_match_p
    s = create_string_scanner("test string")
    assert_equal(4, s.match?(/\w+/))
    assert_equal(4, s.match?(/\w+/))
    assert_equal(nil, s.match?(/\s+/))
  end

  def test_check
    s = create_string_scanner("Foo Bar Baz")
    assert_equal("Foo", s.check(/Foo/))
    assert_equal(0, s.pos)
    assert_equal("Foo", s.matched)
    assert_equal(nil, s.check(/Bar/))
    assert_equal(nil, s.matched)
  end

  def test_scan_full
    s = create_string_scanner("Foo Bar Baz")
    assert_equal(4, s.scan_full(/Foo /, false, false))
    assert_equal(0, s.pos)
    assert_equal(nil, s.scan_full(/Baz/, false, false))
    assert_equal("Foo ", s.scan_full(/Foo /, false, true))
    assert_equal(0, s.pos)
    assert_equal(nil, s.scan_full(/Baz/, false, false))
    assert_equal(4, s.scan_full(/Foo /, true, false))
    assert_equal(4, s.pos)
    assert_equal(nil, s.scan_full(/Baz /, false, false))
    assert_equal("Bar ", s.scan_full(/Bar /, true, true))
    assert_equal(8, s.pos)
    assert_equal(nil, s.scan_full(/az/, false, false))
  end

  def test_exist_p
    s = create_string_scanner("test string")
    assert_equal(3, s.exist?(/s/))
    assert_equal(0, s.pos)
    s.scan(/test/)
    assert_equal(2, s.exist?(/s/))
    assert_equal(4, s.pos)
    assert_equal(nil, s.exist?(/e/))
  end

  def test_exist_p_string
    s = create_string_scanner("test string")
    assert_raise(TypeError) do
      s.exist?(" ")
    end
  end

  def test_skip_until
    s = create_string_scanner("Foo Bar Baz")
    assert_equal(3, s.skip_until(/Foo/))
    assert_equal(3, s.pos)
    assert_equal(4, s.skip_until(/Bar/))
    assert_equal(7, s.pos)
    assert_equal(nil, s.skip_until(/Qux/))
  end

  def test_check_until
    s = create_string_scanner("Foo Bar Baz")
    assert_equal("Foo", s.check_until(/Foo/))
    assert_equal(0, s.pos)
    assert_equal("Foo Bar", s.check_until(/Bar/))
    assert_equal(0, s.pos)
    assert_equal(nil, s.check_until(/Qux/))
  end

  def test_search_full
    s = create_string_scanner("Foo Bar Baz")
    assert_equal(8, s.search_full(/Bar /, false, false))
    assert_equal(0, s.pos)
    assert_equal("Foo Bar ", s.search_full(/Bar /, false, true))
    assert_equal(0, s.pos)
    assert_equal(8, s.search_full(/Bar /, true, false))
    assert_equal(8, s.pos)
    assert_equal("Baz", s.search_full(/az/, true, true))
    assert_equal(11, s.pos)
  end

  def test_peek
    s = create_string_scanner("test string")
    assert_equal("test st", s.peek(7))
    assert_equal("test st", s.peek(7))
    s.scan(/test/)
    assert_equal(" stri", s.peek(5))
    assert_equal(" string", s.peek(10))
    s.scan(/ string/)
    assert_equal("", s.peek(10))
  end

  def test_unscan
    s = create_string_scanner('test string')
    assert_equal("test", s.scan(/\w+/))
    s.unscan
    assert_equal("te", s.scan(/../))
    assert_equal(nil, s.scan(/\d/))
    assert_raise(ScanError) { s.unscan }
  end

  def test_rest
    s = create_string_scanner('test string')
    assert_equal("test string", s.rest)
    s.scan(/test/)
    assert_equal(" string", s.rest)
    s.scan(/ string/)
    assert_equal("", s.rest)
    s.scan(/ string/)
  end

  def test_rest_size
    s = create_string_scanner('test string')
    assert_equal(11, s.rest_size)
    s.scan(/test/)
    assert_equal(7, s.rest_size)
    s.scan(/ string/)
    assert_equal(0, s.rest_size)
    s.scan(/ string/)
  end

  def test_inspect2
    s = create_string_scanner('test string test')
    s.scan(/test strin/)
    assert_equal('#<StringScanner 10/16 "...strin" @ "g tes...">', s.inspect)
  end

  def test_aref_without_regex
    omit "#[:missing] always raises on TruffleRuby if matched" if RUBY_ENGINE == "truffleruby"

    s = create_string_scanner('abc')
    s.get_byte
    assert_nil(s[:c])
    assert_nil(s["c"])
    s.getch
    assert_nil(s[:c])
    assert_nil(s["c"])
  end

  def test_size
    s = create_string_scanner("Fri Dec 12 1975 14:39")
    s.scan(/(\w+) (\w+) (\d+) /)
    assert_equal(4, s.size)
  end

  def test_captures
    s = create_string_scanner("Timestamp: Fri Dec 12 1975 14:39")
    s.scan("Timestamp: ")
    s.scan(/(\w+) (\w+) (\d+) /)
    assert_equal(["Fri", "Dec", "12"], s.captures)
    s.scan(/(\w+) (\w+) (\d+) /)
    assert_nil(s.captures)
  end

  def test_values_at
    s = create_string_scanner("Timestamp: Fri Dec 12 1975 14:39")
    s.scan("Timestamp: ")
    s.scan(/(\w+) (\w+) (\d+) /)
    assert_equal(["Fri Dec 12 ", "12", nil, "Dec"], s.values_at(0, -1, 5, 2))
    s.scan(/(\w+) (\w+) (\d+) /)
    assert_nil(s.values_at(0, -1, 5, 2))
  end

  def test_fixed_anchor_true
    assert_equal(true,  StringScanner.new("a", fixed_anchor: true).fixed_anchor?)
  end

  def test_fixed_anchor_false
    assert_equal(false, StringScanner.new("a").fixed_anchor?)
    assert_equal(false, StringScanner.new("a", true).fixed_anchor?)
    assert_equal(false, StringScanner.new("a", false).fixed_anchor?)
    assert_equal(false, StringScanner.new("a", {}).fixed_anchor?)
    assert_equal(false, StringScanner.new("a", fixed_anchor: nil).fixed_anchor?)
    assert_equal(false, StringScanner.new("a", fixed_anchor: false).fixed_anchor?)
  end

  def test_scan_aref_repeatedly
    s = StringScanner.new('test string')
    assert_equal "test",   s.scan(/\w(\w)(\w*)/)
    assert_equal "test",   s[0]
    assert_equal "e",      s[1]
    assert_equal "st",     s[2]
    assert_nil             s.scan(/\w+/)
    assert_nil             s[0]
    assert_nil             s[1]
    assert_nil             s[2]
    assert_equal " ",      s.scan(/\s+/)
    assert_equal " ",      s[0]
    assert_nil             s[1]
    assert_nil             s[2]
    assert_equal "string", s.scan(/\w(\w)(\w*)/)
    assert_equal "string", s[0]
    assert_equal "t",      s[1]
    assert_equal "ring",   s[2]
  end

  def test_named_captures
    omit("not implemented on TruffleRuby") if ["truffleruby"].include?(RUBY_ENGINE)
    scan = StringScanner.new("foobarbaz")
    assert_equal(9, scan.match?(/(?<f>foo)(?<r>bar)(?<z>baz)/))
    assert_equal({"f" => "foo", "r" => "bar", "z" => "baz"}, scan.named_captures)
  end
end

class TestStringScannerFixedAnchor < TestStringScanner
  def create_string_scanner(string, *args)
    StringScanner.new(string, fixed_anchor: true)
  end

  def test_skip_with_begenning_of_string_anchor_match
    s = create_string_scanner("a")
    assert_equal 1, s.skip(/\Aa/)
  end

  def test_skip_with_begenning_of_string_anchor_not_match
    s = create_string_scanner("a\nb")
    assert_equal 2, s.skip(/a\n/)
    assert_nil      s.skip(/\Ab/)
  end

  def test_skip_with_begenning_of_line_anchor_match
    s = create_string_scanner("a\nb")
    assert_equal 2, s.skip(/a\n/)
    assert_equal 1, s.skip(/^b/)
  end

  def test_skip_with_begenning_of_line_anchor_not_match
    s = create_string_scanner("ab")
    assert_equal 1, s.skip(/a/)
    assert_nil      s.skip(/^b/)
  end
end
