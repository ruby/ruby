require 'test/unit'

$KCODE = 'none'

class TestStringchar < Test::Unit::TestCase
  def test_stringchar
    assert("abcd" == "abcd")
    assert("abcd" =~ /abcd/)
    assert("abcd" === "abcd")
    # compile time string concatenation
    assert("ab" "cd" == "abcd")
    assert("#{22}aa" "cd#{44}" == "22aacd44")
    assert("#{22}aa" "cd#{44}" "55" "#{66}" == "22aacd445566")
    assert("abc" !~ /^$/)
    assert("abc\n" !~ /^$/)
    assert("abc" !~ /^d*$/)
    assert(("abc" =~ /d*$/) == 3)
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
    assert($x == "AC\nAC\n")
    
    assert("foobar" =~ /foo(?=(bar)|(baz))/)
    assert("foobaz" =~ /foo(?=(bar)|(baz))/)
    
    $foo = "abc"
    assert("#$foo = abc" == "abc = abc")
    assert("#{$foo} = abc" == "abc = abc")
    
    foo = "abc"
    assert("#{foo} = abc" == "abc = abc")
    
    assert('-' * 5 == '-----')
    assert('-' * 1 == '-')
    assert('-' * 0 == '')
    
    foo = '-'
    assert(foo * 5 == '-----')
    assert(foo * 1 == '-')
    assert(foo * 0 == '')
    
    $x = "a.gif"
    assert($x.sub(/.*\.([^\.]+)$/, '\1') == "gif")
    assert($x.sub(/.*\.([^\.]+)$/, 'b.\1') == "b.gif")
    assert($x.sub(/.*\.([^\.]+)$/, '\2') == "")
    assert($x.sub(/.*\.([^\.]+)$/, 'a\2b') == "ab")
    assert($x.sub(/.*\.([^\.]+)$/, '<\&>') == "<a.gif>")
    
    # character constants(assumes ASCII)
    assert("a"[0] == ?a)
    assert(?a == ?a)
    assert(?\C-a == 1)
    assert(?\M-a == 225)
    assert(?\M-\C-a == 129)
    assert("a".upcase![0] == ?A)
    assert("A".downcase![0] == ?a)
    assert("abc".tr!("a-z", "A-Z") == "ABC")
    assert("aabbcccc".tr_s!("a-z", "A-Z") == "ABC")
    assert("abcc".squeeze!("a-z") == "abc")
    assert("abcd".delete!("bc") == "ad")
    
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
    assert(s == "another string")
    
    s = <<EOS
#{
[1,2,3].join(",")
}
EOS
    assert(s == "1,2,3\n")
    assert("Just".to_i(36) == 926381)
    assert("-another".to_i(36) == -23200231779)
    assert(1299022.to_s(36) == "ruby")
    assert(-1045307475.to_s(36) == "-hacker")
    assert("Just_another_Ruby_hacker".to_i(36) == 265419172580680477752431643787347)
    assert(-265419172580680477752431643787347.to_s(36) == "-justanotherrubyhacker")
    
    a = []
    (0..255).each {|n|
      ch = [n].pack("C")                     
      a.push ch if /a#{Regexp.quote ch}b/x =~ "ab" 
    }
    assert(a.size == 0)
  end
end
