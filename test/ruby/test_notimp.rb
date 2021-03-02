# frozen_string_literal: false
require 'test/unit'
require 'timeout'
require 'tmpdir'

class TestNotImplement < Test::Unit::TestCase
  def test_respond_to_fork
    assert_include(Process.methods, :fork)
    if /linux/ =~ RUBY_PLATFORM
      assert_equal(true, Process.respond_to?(:fork))
    end
  end

  def test_respond_to_lchmod
    assert_include(File.methods, :lchmod)
    case RUBY_PLATFORM
    when /freebsd/, /linux-musl/
      assert_equal(true, File.respond_to?(:lchmod))
    when /linux/
      assert_equal(false, File.respond_to?(:lchmod))
    end
  end

  def test_call_fork
    GC.start
    pid = nil
    ps =
      case RUBY_PLATFORM
      when /linux/ # assume Linux Distribution uses procps
        proc {`ps -eLf #{pid}`}
      when /freebsd/
        proc {`ps -lH #{pid}`}
      when /darwin/
        proc {`ps -lM #{pid}`}
      else
        proc {`ps -l #{pid}`}
      end
    assert_nothing_raised(Timeout::Error, ps) do
      Timeout.timeout(EnvUtil.apply_timeout_scale(5)) {
        pid = fork {}
        Process.wait pid
        pid = nil
      }
    end
  ensure
    if pid
      Process.kill(:KILL, pid)
      Process.wait pid
    end
  end if Process.respond_to?(:fork)

  def test_call_lchmod
    if File.respond_to?(:lchmod)
      Dir.mktmpdir {|d|
        f = "#{d}/f"
        g = "#{d}/g"
        File.open(f, "w") {}
        File.symlink f, g
        newmode = 0444
        begin
          File.lchmod newmode, "#{d}/g"
        rescue Errno::EOPNOTSUPP
          skip $!
        else
          snew = File.lstat(g)
          assert_equal(newmode, snew.mode & 0777)
        end
      }
    end
  end

  def test_method_inspect_fork
    m = Process.method(:fork)
    if Process.respond_to?(:fork)
      assert_not_match(/not-implemented/, m.inspect)
    else
      assert_match(/not-implemented/, m.inspect)
    end
  end

  def test_method_inspect_lchmod
    m = File.method(:lchmod)
    if File.respond_to?(:lchmod)
      assert_not_match(/not-implemented/, m.inspect)
    else
      assert_match(/not-implemented/, m.inspect)
    end
  end

end
