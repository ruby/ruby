require 'test/unit'

$KCODE = 'none'

class TestStringchar < Test::Unit::TestCase
  def test_string
    assert_equal("abcd", "abcd")
    assert("abcd" =~ /abcd/)
    assert("abcd" === "abcd")
    # compile time string concatenation
    assert_equal("ab" "cd", "abcd")
    assert_equal("#{22}aa" "cd#{44}", "22aacd44")
    assert_equal("#{22}aa" "cd#{44}" "55" "#{66}", "22aacd445566")
    assert("abc" !~ /^$/)
    assert("abc\n" !~ /^$/)
    assert("abc" !~ /^d*$/)
    assert_equal(("abc" =~ /d*$/), 3)
    assert("" =~ /^$/)
    assert("\n" =~ /^$/)
    assert("a\n\n" =~ /^$/)
    assert("abcabc" =~ /.*a/ && $& == "abca")
    assert("abcabc" =~ /.*c/ && $& == "abcabc")
    assert("abcabc" =~ /.*?a/ && $& == "a")
    assert("abcabc" =~ /.*?c/ && $& == "abc")
    assert(/(.|\n)*?\n(b|\n)/ =~ "a\nb\n\n" && $& == "a\nb")
    
    assert(/^(ab+)+b/ =~ "ababb" && $& == "ababb")
    assert(/^(?:ab+)+b/ =~ "ababb" && $& == "ababb")
    assert(/^(ab+)+/ =~ "ababb" && $& == "ababb")
    assert(/^(?:ab+)+/ =~ "ababb" && $& == "ababb")
    
    assert(/(\s+\d+){2}/ =~ " 1 2" && $& == " 1 2")
    assert(/(?:\s+\d+){2}/ =~ " 1 2" && $& == " 1 2")
    
    $x = <<END;
ABCD
ABCD
END
    $x.gsub!(/((.|\n)*?)B((.|\n)*?)D/){$1+$3}
    assert_equal($x, "AC\nAC\n")
    
    assert("foobar" =~ /foo(?=(bar)|(baz))/)
    assert("foobaz" =~ /foo(?=(bar)|(baz))/)
    
    $foo = "abc"
    assert_equal("#$foo = abc", "abc = abc")
    assert_equal("#{$foo} = abc", "abc = abc")
    
    foo = "abc"
    assert_equal("#{foo} = abc", "abc = abc")
    
    assert_equal('-' * 5, '-----')
    assert_equal('-' * 1, '-')
    assert_equal('-' * 0, '')
    
    foo = '-'
    assert_equal(foo * 5, '-----')
    assert_equal(foo * 1, '-')
    assert_equal(foo * 0, '')
    
    $x = "a.gif"
    assert_equal($x.sub(/.*\.([^\.]+)$/, '\1'), "gif")
    assert_equal($x.sub(/.*\.([^\.]+)$/, 'b.\1'), "b.gif")
    assert_equal($x.sub(/.*\.([^\.]+)$/, '\2'), "")
    assert_equal($x.sub(/.*\.([^\.]+)$/, 'a\2b'), "ab")
    assert_equal($x.sub(/.*\.([^\.]+)$/, '<\&>'), "<a.gif>")
  end

  def test_char
    # character constants(assumes ASCII)
    assert_equal("a"[0], ?a)
    assert_equal(?a, ?a)
    assert_equal(?\C-a, 1)
    assert_equal(?\M-a, 225)
    assert_equal(?\M-\C-a, 129)
    assert_equal("a".upcase![0], ?A)
    assert_equal("A".downcase![0], ?a)
    assert_equal("abc".tr!("a-z", "A-Z"), "ABC")
    assert_equal("aabbcccc".tr_s!("a-z", "A-Z"), "ABC")
    assert_equal("abcc".squeeze!("a-z"), "abc")
    assert_equal("abcd".delete!("bc"), "ad")
    
    $x = "abcdef"
    $y = [ ?a, ?b, ?c, ?d, ?e, ?f ]
    $bad = false
    $x.each_byte {|i|
      if i != $y.shift
        $bad = true
        break
      end
    }
    assert(!$bad)
    
    s = "a string"
    s[0..s.size]="another string"
    assert_equal(s, "another string")
    
    s = <<EOS
#{
[1,2,3].join(",")
}
EOS
    assert_equal(s, "1,2,3\n")
    assert_equal("Just".to_i(36), 926381)
    assert_equal("-another".to_i(36), -23200231779)
    assert_equal(1299022.to_s(36), "ruby")
    assert_equal(-1045307475.to_s(36), "-hacker")
    assert_equal("Just_another_Ruby_hacker".to_i(36), 265419172580680477752431643787347)
    assert_equal(-265419172580680477752431643787347.to_s(36), "-justanotherrubyhacker")
    
    a = []
    (0..255).each {|n|
      ch = [n].pack("C")                     
      a.push ch if /a#{Regexp.quote ch}b/x =~ "ab" 
    }
    assert_equal(a.size, 0)
  end
end
