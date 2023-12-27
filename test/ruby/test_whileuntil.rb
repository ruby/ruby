# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestWhileuntil < Test::Unit::TestCase
  def test_while
    Dir.mktmpdir("ruby_while_tmp") {|tmpdir|
      tmpfilename = "#{tmpdir}/ruby_while_tmp.#{$$}"

      tmp = open(tmpfilename, "w")
      tmp.print "tvi925\n";
      tmp.print "tvi920\n";
      tmp.print "vt100\n";
      tmp.print "Amiga\n";
      tmp.print "paper\n";
      tmp.close

      tmp = open(tmpfilename, "r")
      assert_instance_of(File, tmp)

      while line = tmp.gets()
        break if /vt100/ =~ line
      end

      assert_not_predicate(tmp, :eof?)
      assert_match(/vt100/, line)
      tmp.close

      tmp = open(tmpfilename, "r")
      while line = tmp.gets()
        next if /vt100/ =~ line
        assert_no_match(/vt100/, line)
      end
      assert_predicate(tmp, :eof?)
      assert_no_match(/vt100/, line)
      tmp.close

      tmp = open(tmpfilename, "r")
      while line = tmp.gets()
        lastline = line
        line = line.gsub(/vt100/, 'VT100')
        if lastline != line
          line.gsub!('VT100', 'Vt100')
          redo
        end
        assert_no_match(/vt100/, line)
        assert_no_match(/VT100/, line)
      end
      assert_predicate(tmp, :eof?)
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

      tmp = open(tmpfilename, "r")
      while line = tmp.gets()
        break if $. == 3
        assert_no_match(/vt100/, line)
        assert_no_match(/Amiga/, line)
        assert_no_match(/paper/, line)
      end
      tmp.close

      File.unlink tmpfilename or `/bin/rm -f "#{tmpfilename}"`
      assert_file.not_exist?(tmpfilename)
    }
  end

  def test_begin_while
    i = 0
    sum = 0
    begin
      i += 1
      sum += i
    end while i < 10
    assert_equal([10, 55], [i, sum])

    i = 0
    sum = 0
    (
      i += 1
      sum += i
    ) while false
    assert_equal([0, 0], [i, sum])
  end

  def test_until
    i = 0
    until i>4
      i+=1
    end
    assert_operator(i, :>, 4)
  end
end
