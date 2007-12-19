assert_normal_exit %q{
  "abcdefghij\xf0".force_encoding("utf-8").reverse.inspect
}, '[ruby-dev:32448]'

assert_equal 'true', %q{
  "abc".sub(/b/, "\xa1\xa1".force_encoding("euc-jp")) ==
  "a\xa1\xa1c".force_encoding("euc-jp")
}

assert_equal 'ok', %q{
  begin
    if ("\xa1\xa2\xa1\xa3").force_encoding("euc-jp").split(//) ==
      ["\xa1\xa2".force_encoding("euc-jp"), "\xa1\xa3".force_encoding("euc-jp")]
      :ok
    else
      :ng
    end
  rescue
    :ng
  end
}, '[ruby-dev:32452]'

assert_equal 'ok', %q{
  begin
    "\xa1\xa1".force_encoding("euc-jp") + "\xa1".force_encoding("ascii-8bit")
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'ok', %q{
  begin
    "%s%s" % ["\xc2\xa1".force_encoding("sjis"), "\xc2\xa1".force_encoding("euc-jp")]
  rescue ArgumentError
    :ok
  end
}

assert_equal '0', %q{
  "\xa1\xa2".force_encoding("euc-jp").count("z")
}

assert_equal '1', %q{
  "\xa1\xa2".force_encoding("euc-jp").delete("z").length
}

assert_equal 'false', %q{
  "\xa1\xa2\xa3\xa4".force_encoding("euc-jp").include?("\xa3".force_encoding("euc-jp"))
}

assert_equal 'ok', %q{
  "\xa1\xa2\xa3\xa4".force_encoding("euc-jp").index("\xa3".force_encoding("euc-jp")) or :ok
}

assert_equal 'ok', %q{
  "\xa1\xa2\xa3\xa4".force_encoding("euc-jp").rindex("\xa3".force_encoding("euc-jp")) or :ok
}

assert_equal 'false', %q{
  s1 = "\xa1\xa1".force_encoding("euc-jp")
  s2 = s1.dup
  (94*94+94).times { s2.next! }
  s1 == s2
}

assert_equal 'ok', %q{
  "\xa1\xa2a\xa3\xa4".force_encoding("euc-jp").scan(/a/)
  :ok
}

assert_equal 'ok', %q{
  "\xa1\xa2a\xa3\xa4".force_encoding("euc-jp").split(/a/)
  :ok
}

assert_equal 'ok', %q{
  s1 = "\xa1\xa2".force_encoding("euc-jp")
  s2 = "\xa1\xa2".force_encoding("sjis")
  begin
    s1.upto(s2) {|x| break }
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'true', %q{
  "%s" % "\xa1\xa1".force_encoding("euc-jp") ==
  "\xa1\xa1".force_encoding("euc-jp")
}

assert_equal 'a', %q{
  s = "a".dup.force_encoding("EUC-JP")
  s.length
  s[0,2]
}

assert_equal 'ok', %q{
  s1 = "\x81\x41".force_encoding("sjis")
  s2 = "\x81\x61".force_encoding("sjis")
  s1.casecmp(s2) == 0 ? :ng : :ok
}

assert_equal 'EUC-JP', %q{ ("\xc2\xa1 %s".force_encoding("EUC-JP") % "foo").encoding.name }
assert_equal 'true', %q{ "\xa1\xa2\xa3\xa4".force_encoding("euc-jp")["\xa2\xa3".force_encoding("euc-jp")] == nil }
assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s["\xb0\xa3"] = "foo"
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'EUC-JP', %q{ "\xa3\xb0".force_encoding("EUC-JP").center(10).encoding.name }

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s.chomp("\xa3\xb4".force_encoding("shift_jis"))
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s.count("\xa3\xb0".force_encoding("ascii-8bit"))
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s.delete("\xa3\xb2".force_encoding("ascii-8bit")) 
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s.each_line("\xa3\xb1".force_encoding("ascii-8bit")) {|l| }    
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'true', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  s.gsub(/\xa3\xb1/e, "z") == "\xa3\xb0z\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
}

assert_equal 'false', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  s.include?("\xb0\xa3".force_encoding("euc-jp"))
}

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  s.index("\xb3\xa3".force_encoding("euc-jp")) or :ok
}

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  s.insert(-1, "a")
  :ok
}

assert_finish 1, %q{ "\xa3\xfe".force_encoding("euc-jp").next }

assert_equal 'ok', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  begin
    s.rindex("\xb1\xa3".force_encoding("ascii-8bit"))
    :ng
  rescue ArgumentError
    :ok
  end
}

assert_equal 'true', %q{
  s = "\xa3\xb0\xa3\xb1\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  s.split("\xa3\xb1".force_encoding("euc-jp")) == [
    "\xa3\xb0".force_encoding("euc-jp"),
    "\xa3\xb2\xa3\xb3\xa3\xb4".force_encoding("euc-jp")
  ]
}, '[ruby-dev:32452]'

assert_normal_exit %q{ // =~ :a }
