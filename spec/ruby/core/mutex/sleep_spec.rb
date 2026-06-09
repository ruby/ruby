require_relative '../../spec_helper'

describe "Mutex#sleep" do
  describe "when not locked by the current thread" do
    it "raises a ThreadError" do
      m = Mutex.new
      -> { m.sleep }.should.raise(ThreadError)
    end

    it "raises an ArgumentError if passed a negative duration" do
      m = Mutex.new
      -> { m.sleep(-0.1) }.should.raise(ArgumentError)
      -> { m.sleep(-1) }.should.raise(ArgumentError)
    end
  end

  it "raises an ArgumentError if passed a negative duration" do
    m = Mutex.new
    m.lock
    -> { m.sleep(-0.1) }.should.raise(ArgumentError)
    -> { m.sleep(-1) }.should.raise(ArgumentError)
  end

  it "pauses execution for approximately the duration requested" do
    m = Mutex.new
    m.lock
    duration = 0.001
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    m.sleep duration
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (now - start).should >= 0
    (now - start).should < (duration + TIME_TOLERANCE)
  end

  it "unlocks the mutex while sleeping" do
    m = Mutex.new
    locked = false
    th = Thread.new { m.lock; locked = true; m.sleep }
    Thread.pass until locked
    Thread.pass until th.stop?
    m.locked?.should == false
    th.run
    th.join
  end

  it "relocks the mutex when woken" do
    m = Mutex.new
    m.lock
    m.sleep(0.001)
    m.locked?.should == true
  end

  it "relocks the mutex when woken by an exception being raised" do
    m = Mutex.new
    locked = false
    th = Thread.new do
      m.lock
      locked = true
      begin
        m.sleep
      rescue Exception
        m.locked?
      end
    end
    Thread.pass until locked
    Thread.pass until th.stop?
    th.raise(Exception)
    th.value.should == true
  end

  it "returns the rounded number of seconds asleep" do
    m = Mutex.new
    locked = false
    th = Thread.start do
      m.lock
      locked = true
      m.sleep
    end
    Thread.pass until locked
    Thread.pass until th.stop?
    th.wakeup
    th.value.should.is_a?(Integer)
  end

  it "accepts nil as a sleep duration" do
    m = Mutex.new
    -> {
      m.lock
      m.sleep(nil)
    }.should block_caller
  end

  it "wakes up when requesting sleep times near or equal to zero" do
    times = []
    val = 1

    # power of two divisor so we eventually get near zero
    loop do
      val = val / 16.0
      times << val
      break if val == 0.0
    end

    m = Mutex.new
    m.lock
    times.each do |time|
      # just testing that sleep completes
      -> {m.sleep(time)}.should_not.raise
    end
  end
end
