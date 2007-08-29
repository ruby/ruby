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
      begin
        Process.setrlimit(Process::RLIMIT_NOFILE, 0, max_nofile)
      rescue Errno::EINVAL
        exit 0
      end
      begin
        IO.pipe
      rescue Errno::EMFILE
        exit 0
      end
      exit 1
    }
    Process.wait pid
    assert_equal(0, $?.to_i)
  end
end
