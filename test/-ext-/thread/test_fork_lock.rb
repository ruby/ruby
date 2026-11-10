# frozen_string_literal: false
require 'test/unit'

class TestThreadForkLock < Test::Unit::TestCase
  def setup
    omit "fork not supported" unless Process.respond_to?(:fork)
  end

  def test_fork_while_another_thread_waits_for_fork_lock
    assert_separately([], <<-'RUBY')
      require '-test-/thread/fork_lock'

      Bug::ThreadForkLock.contend do
        20.times do
          pid = fork do
            # the child's copy of the lock has to keep working, too
            Bug::ThreadForkLock.contend do
              5.times do
                _, status = Process.wait2(fork { exit!(0) })
                exit!(false) unless status.success?
              end
            end
            exit!(true)
          end
          th = Process.detach(pid)
          unless th.join(EnvUtil.apply_timeout_scale(5))
            Process.kill(:KILL, pid)
          end
          assert_predicate(th.value, :success?, "[Bug #22445]")
        end
      end
    RUBY
  end
end
