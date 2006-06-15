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
    cur_nofile, max_nofile = Process.getrlimit(Process::RLIMIT_NOFILE)
    Process.setrlimit(Process::RLIMIT_NOFILE, 0, max_nofile)
    begin
      assert_raise(Errno::EMFILE) { IO.pipe }
    ensure
      Process.setrlimit(Process::RLIMIT_NOFILE, cur_nofile, max_nofile)
    end
  end
end
