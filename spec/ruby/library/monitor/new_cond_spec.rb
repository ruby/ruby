require_relative '../../spec_helper'
require 'monitor'

describe "Monitor#new_cond" do
  it "creates a MonitorMixin::ConditionVariable" do
    m = Monitor.new
    c = m.new_cond
    c.class.should == MonitorMixin::ConditionVariable
  end

  it 'returns a condition variable which can be waited on by a thread holding the monitor' do
    m = Monitor.new
    c = m.new_cond

    10.times do

      wait_q = Queue.new
      thread = Thread.new do
        m.synchronize do
          wait_q << true
          c.wait
        end
        :done
      end

      wait_q.pop

      # Synchronize can't happen until the other thread is waiting.
      m.synchronize { c.signal }

      thread.join
      thread.value.should == :done
    end
  end

  it 'returns a condition variable which can be waited on by a thread holding the monitor inside multiple synchronize blocks' do
    m = Monitor.new
    c = m.new_cond

    10.times do

      wait_q = Queue.new
      thread = Thread.new do
        m.synchronize do
          m.synchronize do
            wait_q << true
            c.wait
          end
        end
        :done
      end

      wait_q.pop

      #No need to wait here as we cannot synchronize until the other thread is waiting.
      m.synchronize { c.signal }

      thread.join
      thread.value.should == :done
    end
  end

  it 'returns a condition variable which can be signalled by a thread holding the monitor inside multiple synchronize blocks' do
    m = Monitor.new
    c = m.new_cond

    10.times do

      wait_q = Queue.new
      thread = Thread.new do
        m.synchronize do
          wait_q << true
          c.wait
        end
        :done
      end

      wait_q.pop

      # Synchronize can't happen until the other thread is waiting.
      m.synchronize { m.synchronize { c.signal } }

      thread.join
      thread.value.should == :done
    end
  end

end
