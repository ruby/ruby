require_relative '../../spec_helper'

describe "ConditionVariable#signal" do
  it "releases the first thread waiting in line for this resource" do
    m = Mutex.new
    cv = ConditionVariable.new
    threads = []
    r1 = []
    r2 = []

    # large number to attempt to cause race conditions
    100.times do |i|
      threads << Thread.new(i) do |tid|
        m.synchronize do
          r1 << tid
          cv.wait(m)
          r2 << tid
        end
      end
    end

    # wait for all threads to acquire the mutex the first time
    Thread.pass until m.synchronize { r1.size == threads.size }
    # wait until all threads are sleeping (ie waiting)
    Thread.pass until threads.all?(&:stop?)

    r2.should be_empty
    100.times do |i|
      m.synchronize do
        cv.signal
      end
      Thread.pass until r2.size == i+1
    end

    threads.each {|t| t.join }

    # ensure that all the threads that went into the cv.wait are
    # released in the same order
    r2.should == r1
  end

  it "allows control to be passed between a pair of threads" do
    m = Mutex.new
    cv = ConditionVariable.new
    repeats = 100
    in_synchronize = false

    t1 = Thread.new do
      m.synchronize do
        in_synchronize = true
        repeats.times do
          cv.wait(m)
          cv.signal
        end
      end
    end

    # Make sure t1 is waiting for a signal before launching t2.
    Thread.pass until in_synchronize
    Thread.pass until t1.stop?

    t2 = Thread.new do
      m.synchronize do
        repeats.times do
          cv.signal
          cv.wait(m)
        end
      end
    end

    # Check that both threads terminated without exception
    t1.join
    t2.join
    m.should_not.locked?
  end
end
