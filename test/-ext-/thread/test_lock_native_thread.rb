# frozen_string_literal: false

require 'envutil'

mn_supported_p = -> do
  out, *_ = EnvUtil.invoke_ruby([{'RUBY_MN_THREADS' => '1'}, '-v'], '', true)
  return /\+MN/ =~ out
end

if mn_supported_p.call
  # test only on MN threads
else
  return
end

class TestThreadLockNativeThread < Test::Unit::TestCase
  def test_lock_native_thread
    assert_separately([{'RUBY_MN_THREADS' => '1'}], <<-RUBY)
      require '-test-/thread/lock_native_thread'

      Thread.new{
        assert_equal true, Thread.current.lock_native_thread
      }.join

      # main thread already has DNT
      assert_equal false, Thread.current.lock_native_thread
    RUBY
  end

  def test_lock_native_thread_tls
    assert_separately([{'RUBY_MN_THREADS' => '1'}], <<-RUBY)
      require '-test-/thread/lock_native_thread'
      tn = 10
      ln = 1_000

      ts = tn.times.map{|i|
        Thread.new(i){|i|
          Thread.current.set_tls i
          assert_equal true, Thread.current.lock_native_thread

          ln.times{
            assert_equal i, Thread.current.get_tls
            Thread.pass
          }
        }
      }
      ts.each(&:join)
    RUBY
  end
end
