require 'test/unit'

$KCODE = 'none'

class TestWhileuntil < Test::Unit::TestCase
  def test_while
    tmp = open("while_tmp", "w")
    tmp.print "tvi925\n";
    tmp.print "tvi920\n";
    tmp.print "vt100\n";
    tmp.print "Amiga\n";
    tmp.print "paper\n";
    tmp.close

    tmp = open("while_tmp", "r")
    assert(tmp.kind_of?(File))
    
    while line = tmp.gets()
      break if /vt100/ =~ line
    end
    
    assert(!tmp.eof? && /vt100/ =~ line)
    tmp.close

    $bad = false
    tmp = open("while_tmp", "r")
    while line = tmp.gets()
      next if /vt100/ =~ line
      $bad = 1 if /vt100/ =~ line
    end
    assert(!(!tmp.eof? || /vt100/ =~ line || $bad))
    tmp.close
    
    $bad = false
    tmp = open("while_tmp", "r")
    while tmp.gets()
      line = $_
      gsub(/vt100/, 'VT100')
      if $_ != line
        $_.gsub!('VT100', 'Vt100')
        redo
      end
      $bad = 1 if /vt100/ =~ $_
      $bad = 1 if /VT100/ =~ $_
    end
    assert(tmp.eof? && !$bad)
    tmp.close
    
    sum=0
    for i in 1..10
      sum += i
      i -= 1
      if i > 0
        redo
      end
    end
    assert(sum == 220)
    
    $bad = false
    tmp = open("while_tmp", "r")
    while line = tmp.gets()
      break if 3
      case line
      when /vt100/, /Amiga/, /paper/
        $bad = true
      end
    end
    assert(!$bad)
    tmp.close
    
    File.unlink "while_tmp" or `/bin/rm -f "while_tmp"`
    assert(!File.exist?("while_tmp"))
  end

  def test_until
    i = 0
    until i>4
      i+=1
    end
    assert(i>4)
  end
end
