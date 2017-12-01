require File.expand_path('../../../spec_helper', __FILE__)

describe "Mutex#sleep" do
  describe "when not locked by the current thread" do
    it "raises a ThreadError" do
      m = Mutex.new
      lambda { m.sleep }.should raise_error(ThreadError)
    end

    it "raises an ArgumentError if passed a negative duration" do
      m = Mutex.new
      lambda { m.sleep(-0.1) }.should raise_error(ArgumentError)
      lambda { m.sleep(-1) }.should raise_error(ArgumentError)
    end
  end

  it "raises an ArgumentError if passed a negative duration" do
    m = Mutex.new
    m.lock
    lambda { m.sleep(-0.1) }.should raise_error(ArgumentError)
    lambda { m.sleep(-1) }.should raise_error(ArgumentError)
  end

  it "pauses execution for approximately the duration requested" do
    m = Mutex.new
    m.lock
    duration = 0.1
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    m.sleep duration
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (now - start).should > 0
    (now - start).should < 2.0
  end

  it "unlocks the mutex while sleeping" do
    m = Mutex.new
    locked = false
    th = Thread.new { m.lock; locked = true; m.sleep }
    Thread.pass until locked
    Thread.pass while th.status and th.status != "sleep"
    m.locked?.should be_false
    th.run
    th.join
  end

  it "relocks the mutex when woken" do
    m = Mutex.new
    m.lock
    m.sleep(0.01)
    m.locked?.should be_true
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
    Thread.pass while th.status and th.status != "sleep"
    th.raise(Exception)
    th.value.should be_true
  end

  it "returns the rounded number of seconds asleep" do
    m = Mutex.new
    m.lock
    m.sleep(0.01).should be_kind_of(Integer)
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
      m.sleep(time).should_not == nil
    end
  end
end
