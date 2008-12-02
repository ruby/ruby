require 'test/unit'
require 'open3'
require 'shellwords'
require_relative 'ruby/envutil'

class TestOpen3 < Test::Unit::TestCase
  RUBY = EnvUtil.rubybin

  def test_exit_status
    Open3.popen3(RUBY, '-e', 'exit true') {|i,o,e,t|
      assert_equal(true, t.value.success?)
    }
    Open3.popen3(RUBY, '-e', 'exit false') {|i,o,e,t|
      assert_equal(false, t.value.success?)
    }
  end

  def test_stdin
    Open3.popen3(RUBY, '-e', 'exit STDIN.gets.chomp == "t"') {|i,o,e,t|
      i.puts 't'
      assert_equal(true, t.value.success?)
    }
    Open3.popen3(RUBY, '-e', 'exit STDIN.gets.chomp == "t"') {|i,o,e,t|
      i.puts 'f'
      assert_equal(false, t.value.success?)
    }
  end

  def test_stdout
    Open3.popen3(RUBY, '-e', 'STDOUT.print "foo"') {|i,o,e,t|
      assert_equal("foo", o.read)
    }
  end

  def test_stderr
    Open3.popen3(RUBY, '-e', 'STDERR.print "bar"') {|i,o,e,t|
      assert_equal("bar", e.read)
    }
  end

  def test_block
    r = Open3.popen3(RUBY, '-e', 'STDOUT.print STDIN.read') {|i,o,e,t|
      i.print "baz"
      i.close
      assert_equal("baz", o.read)
      "qux"
    }
    assert_equal("qux", r)
  end

  def test_noblock
    i,o,e,t = Open3.popen3(RUBY, '-e', 'STDOUT.print STDIN.read')
    i.print "baz"
    i.close
    assert_equal("baz", o.read)
  ensure
    i.close if !i.closed?
    o.close if !o.closed?
    e.close if !e.closed?
  end

  def test_commandline
    commandline = Shellwords.join([RUBY, '-e', 'print "quux"'])
    Open3.popen3(commandline) {|i,o,e,t|
      assert_equal("quux", o.read)
    }
  end

  def test_pid
    Open3.popen3(RUBY, '-e', 'print $$') {|i,o,e,t|
      pid = o.read.to_i
      assert_equal(pid, t[:pid])
      assert_equal(pid, t.pid)
    }
  end

  def test_disable
    Open3.popen3(RUBY, '-e', '', STDIN=>nil) {|o,e,t|
      assert_kind_of(Thread, t)
    }
    Open3.popen3(RUBY, '-e', '', STDOUT=>nil) {|i,e,t|
      assert_kind_of(Thread, t)
    }
    Open3.popen3(RUBY, '-e', '', STDERR=>nil) {|i,o,t|
      assert_kind_of(Thread, t)
    }
    Open3.popen3(RUBY, '-e', '', STDIN=>nil, STDOUT=>nil, STDERR=>nil) {|t|
      assert_kind_of(Thread, t)
    }
  end

  def with_pipe
    r, w = IO.pipe
    yield r, w
  ensure
    r.close if !r.closed?
    w.close if !w.closed?
  end

  def with_reopen(io, arg)
    old = io.dup
    io.reopen(arg)
    yield old
  ensure
    io.reopen(old)
    old.close if old && !old.closed?
  end

  def test_disable_stdin
    with_pipe {|r, w|
      with_reopen(STDIN, r) {|old|
        Open3.popen3(RUBY, '-e', 's=STDIN.read; STDOUT.print s+"o"; STDERR.print s+"e"', STDIN=>nil) {|o,e,t|
          assert_kind_of(Thread, t)
          w.print "x"
          w.close
          assert_equal("xo", o.read)
          assert_equal("xe", e.read)
        }
      }
    }
  end

  def test_disable_stdout
    with_pipe {|r, w|
      with_reopen(STDOUT, w) {|old|
        w.close
        Open3.popen3(RUBY, '-e', 's=STDIN.read; STDOUT.print s+"o"; STDERR.print s+"e"', STDOUT=>nil) {|i,e,t|
          assert_kind_of(Thread, t)
          i.print "y"
          i.close
          STDOUT.reopen(old)
          assert_equal("yo", r.read)
          assert_equal("ye", e.read)
        }
      }
    }
  end

  def test_disable_stderr
    with_pipe {|r, w|
      with_reopen(STDERR, w) {|old|
        w.close
        Open3.popen3(RUBY, '-e', 's=STDIN.read; STDOUT.print s+"o"; STDERR.print s+"e"', STDERR=>nil) {|i,o,t|
          assert_kind_of(Thread, t)
          i.print "y"
          i.close
          STDERR.reopen(old)
          assert_equal("yo", o.read)
          assert_equal("ye", r.read)
        }
      }
    }
  end

  def test_plug_pipe
    Open3.popen3(RUBY, '-e', 'STDOUT.print "1"') {|i1,o1,e1,t1|
      Open3.popen3(RUBY, '-e', 'STDOUT.print STDIN.read+"2"', STDIN=>o1) {|o2,e2,t2|
        assert_equal("12", o2.read)
      }
    }
  end

  def test_tree_pipe
    ia,oa,ea,ta = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"a"; STDERR.print i+"A"')
    ob,eb,tb = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"b"; STDERR.print i+"B"', STDIN=>oa)
    oc,ec,tc = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"c"; STDERR.print i+"C"', STDIN=>ob)
    od,ed,td = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"d"; STDERR.print i+"D"', STDIN=>eb)
    oe,ee,te = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"e"; STDERR.print i+"E"', STDIN=>ea)
    of,ef,tf = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"f"; STDERR.print i+"F"', STDIN=>oe)
    og,eg,tg = Open3.popen3(RUBY, '-e', 'i=STDIN.read; STDOUT.print i+"g"; STDERR.print i+"G"', STDIN=>ee)
    oa.close
    ea.close
    ob.close
    eb.close
    oe.close
    ee.close

    ia.print "0"
    ia.close
    assert_equal("0abc", oc.read)
    assert_equal("0abC", ec.read)
    assert_equal("0aBd", od.read)
    assert_equal("0aBD", ed.read)
    assert_equal("0Aef", of.read)
    assert_equal("0AeF", ef.read)
    assert_equal("0AEg", og.read)
    assert_equal("0AEG", eg.read)
  ensure
    ia.close if !ia.closed?
    oa.close if !oa.closed?
    ea.close if !ea.closed?
    ob.close if !ob.closed?
    eb.close if !eb.closed?
    oc.close if !oc.closed?
    ec.close if !ec.closed?
    od.close if !od.closed?
    ed.close if !ed.closed?
    oe.close if !oe.closed?
    ee.close if !ee.closed?
    of.close if !of.closed?
    ef.close if !ef.closed?
    og.close if !og.closed?
    eg.close if !eg.closed?
  end
end
