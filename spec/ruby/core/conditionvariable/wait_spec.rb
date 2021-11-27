require_relative '../../spec_helper'
require 'thread'

describe "ConditionVariable#wait" do
  it "calls #sleep on the given object" do
    o = Object.new
    o.should_receive(:sleep).with(1234)

    cv = ConditionVariable.new

    cv.wait(o, 1234)
  end

  it "can be woken up by ConditionVariable#signal" do
    m = Mutex.new
    cv = ConditionVariable.new
    in_synchronize = false

    th = Thread.new do
      m.synchronize do
        in_synchronize = true
        cv.wait(m)
      end
      :success
    end

    # wait for m to acquire the mutex
    Thread.pass until in_synchronize
    # wait until th is sleeping (ie waiting)
    Thread.pass until th.stop?

    m.synchronize { cv.signal }
    th.value.should == :success
  end

  it "can be interrupted by Thread#run" do
    m = Mutex.new
    cv = ConditionVariable.new
    in_synchronize = false

    th = Thread.new do
      m.synchronize do
        in_synchronize = true
        cv.wait(m)
      end
      :success
    end

    # wait for m to acquire the mutex
    Thread.pass until in_synchronize
    # wait until th is sleeping (ie waiting)
    Thread.pass until th.stop?

    th.run
    th.value.should == :success
  end

  it "can be interrupted by Thread#wakeup" do
    m = Mutex.new
    cv = ConditionVariable.new
    in_synchronize = false

    th = Thread.new do
      m.synchronize do
        in_synchronize = true
        cv.wait(m)
      end
      :success
    end

    # wait for m to acquire the mutex
    Thread.pass until in_synchronize
    # wait until th is sleeping (ie waiting)
    Thread.pass until th.stop?

    th.wakeup
    th.value.should == :success
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
    Thread.pass until th.stop?

    th.kill
    th.join

    owned.should == true
  end

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
    Thread.pass until th.stop?

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
    Thread.pass until threads.any?(&:stop?)
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
