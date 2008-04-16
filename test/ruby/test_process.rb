require 'test/unit'

class TestProcess < Test::Unit::TestCase
  def test_rlimit_availability
    begin
      Process.getrlimit(nil)
    rescue NotImplementedError
      assert_raise(NotImplementedError) { Process.setrlimit }
    rescue TypeError
      assert_raise(ArgumentError) { Process.setrlimit }
    end
  end

  def rlimit_exist?
    Process.getrlimit(nil)
  rescue NotImplementedError
    return false
  rescue TypeError
    return true
  end

  def test_rlimit_nofile
    return unless rlimit_exist?
    pid = fork {
      cur_nofile, max_nofile = Process.getrlimit(Process::RLIMIT_NOFILE)
      result = 1
      begin
        Process.setrlimit(Process::RLIMIT_NOFILE, 0, max_nofile)
      rescue Errno::EINVAL
        result = 0
      end
      if result == 1
        begin
          IO.pipe
        rescue Errno::EMFILE
         result = 0
        end
      end
      Process.setrlimit(Process::RLIMIT_NOFILE, cur_nofile, max_nofile)
      exit result
    }
    Process.wait pid
    assert_equal(0, $?.to_i, "#{$?}")
  end

  def test_rlimit_name
    return unless rlimit_exist?
    [
      :AS, "AS",
      :CORE, "CORE",
      :CPU, "CPU",
      :DATA, "DATA",
      :FSIZE, "FSIZE",
      :MEMLOCK, "MEMLOCK",
      :NOFILE, "NOFILE",
      :NPROC, "NPROC",
      :RSS, "RSS",
      :STACK, "STACK",
      :SBSIZE, "SBSIZE",
    ].each {|name|
      if Process.const_defined? "RLIMIT_#{name}"
        assert_nothing_raised { Process.getrlimit(name) }
      else
        assert_raise(ArgumentError) { Process.getrlimit(name) }
      end
    }
    assert_raise(ArgumentError) { Process.getrlimit(:FOO) }
    assert_raise(ArgumentError) { Process.getrlimit("FOO") }
  end

  def test_rlimit_value
    return unless rlimit_exist?
    assert_raise(ArgumentError) { Process.setrlimit(:CORE, :FOO) }
    assert_raise(Errno::EPERM) { Process.setrlimit(:NOFILE, :INFINITY) }
    assert_raise(Errno::EPERM) { Process.setrlimit(:NOFILE, "INFINITY") }
  end
end
