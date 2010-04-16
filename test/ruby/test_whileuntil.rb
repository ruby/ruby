require 'test/unit'

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
    assert_instance_of(File, tmp)

    while line = tmp.gets()
      break if /vt100/ =~ line
    end

    assert(!tmp.eof?)
    assert_match(/vt100/, line)
    tmp.close

    tmp = open("while_tmp", "r")
    while line = tmp.gets()
      next if /vt100/ =~ line
      assert_no_match(/vt100/, line)
    end
    assert(tmp.eof?)
    assert_no_match(/vt100/, line)
    tmp.close

    tmp = open("while_tmp", "r")
    while tmp.gets()
      line = $_
      gsub(/vt100/, 'VT100')
      if $_ != line
        $_.gsub!('VT100', 'Vt100')
        redo
      end
      assert_no_match(/vt100/, $_)
      assert_no_match(/VT100/, $_)
    end
    assert(tmp.eof?)
    tmp.close

    sum=0
    for i in 1..10
      sum += i
      i -= 1
      if i > 0
        redo
      end
    end
    assert_equal(220, sum)

    tmp = open("while_tmp", "r")
    while line = tmp.gets()
      break if 3
      assert_no_match(/vt100/, line)
      assert_no_match(/Amiga/, line)
      assert_no_match(/paper/, line)
    end
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
