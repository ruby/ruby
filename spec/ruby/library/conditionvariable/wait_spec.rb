require_relative '../../spec_helper'
require 'thread'

describe "ConditionVariable#wait" do
  it "calls #sleep on the given object" do
    o = Object.new
    o.should_receive(:sleep).with(1234)

    cv = ConditionVariable.new

    cv.wait(o, 1234)
  end

  it "returns self" do
    m = Mutex.new
    cv = ConditionVariable.new
    in_synchronize = false

    th = Thread.new do
      m.synchronize do
        in_synchronize = true
        cv.wait(m).should == cv
      end
    end

    # wait for m to acquire the mutex
    Thread.pass until in_synchronize
    # wait until th is sleeping (ie waiting)
    Thread.pass while th.status and th.status != "sleep"

    m.synchronize { cv.signal }
    th.join
  end

  it "reacquires the lock even if the thread is killed" do
    m = Mutex.new
    cv = ConditionVariable.new
    in_synchronize = false
    owned = nil

    th = Thread.new do
      m.synchronize do
        in_synchronize = true
        begin
          cv.wait(m)
        ensure
          owned = m.owned?
          $stderr.puts "\nThe Thread doesn't own the Mutex!" unless owned
        end
      end
    end

    # wait for m to acquire the mutex
    Thread.pass until in_synchronize
    # wait until th is sleeping (ie waiting)
    Thread.pass while th.status and th.status != "sleep"

    th.kill
    th.join

    owned.should == true
  end

  ruby_bug '#14999', ''...'2.5' do
    it "reacquires the lock even if the thread is killed after being signaled" do
      m = Mutex.new
      cv = ConditionVariable.new
      in_synchronize = false
      owned = nil

      th = Thread.new do
        m.synchronize do
          in_synchronize = true
          begin
            cv.wait(m)
          ensure
            owned = m.owned?
            $stderr.puts "\nThe Thread doesn't own the Mutex!" unless owned
          end
        end
      end

      # wait for m to acquire the mutex
      Thread.pass until in_synchronize
      # wait until th is sleeping (ie waiting)
      Thread.pass while th.status and th.status != "sleep"

      m.synchronize {
        cv.signal
        # Wait that the thread is blocked on acquiring the Mutex
        sleep 0.001
        # Kill the thread, yet the thread should first acquire the Mutex before going on
        th.kill
      }

      th.join
      owned.should == true
    end
  end

  it "supports multiple Threads waiting on the same ConditionVariable and Mutex" do
    m = Mutex.new
    cv = ConditionVariable.new
    n_threads = 4
    events = []

    threads = n_threads.times.map {
      Thread.new {
        m.synchronize {
          events << :t_in_synchronize
          cv.wait(m)
        }
      }
    }

    Thread.pass until m.synchronize { events.size } == n_threads
    Thread.pass while threads.any? { |th| th.status and th.status != "sleep" }
    m.synchronize do
      threads.each { |t|
        # Cause interactions with the waiting threads.
        # On TruffleRuby, this causes a safepoint which has interesting
        # interactions with the ConditionVariable.
        bt = t.backtrace
        bt.should be_kind_of(Array)
        bt.size.should >= 2
      }
    end

    cv.broadcast
    threads.each(&:join)
  end
end
