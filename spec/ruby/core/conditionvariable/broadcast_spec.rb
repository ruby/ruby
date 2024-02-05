require_relative '../../spec_helper'

describe "ConditionVariable#broadcast" do
  it "releases all threads waiting in line for this resource" do
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
    m.synchronize do
      cv.broadcast
    end

    threads.each {|t| t.join }

    # ensure that all threads that enter cv.wait are released
    r2.sort.should == r1.sort
    # note that order is not specified as broadcast results in a race
    # condition on regaining the lock m
  end
end
