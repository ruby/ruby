require_relative '../fixtures/classes'

describe :time_now, shared: true do
  it "creates a subclass instance if called on a subclass" do
    TimeSpecs::SubTime.send(@method).should be_an_instance_of(TimeSpecs::SubTime)
    TimeSpecs::MethodHolder.send(@method).should be_an_instance_of(Time)
  end

  it "sets the current time" do
    now = TimeSpecs::MethodHolder.send(@method)
    now.to_f.should be_close(Process.clock_gettime(Process::CLOCK_REALTIME), TIME_TOLERANCE)
  end

  it "uses the local timezone" do
    with_timezone("PDT", -8) do
      now = TimeSpecs::MethodHolder.send(@method)
      now.utc_offset.should == (-8 * 60 * 60)
    end
  end

  it "has at least microsecond precision" do
    # The clock should not be less accurate than expected (times should
    # not all be a multiple of the next precision up, assuming precisions
    # are multiples of ten.)
    expected = 1_000
    t = 0
    10_000.times.find do
      t = Time.now.nsec
      t % (expected * 10) != 0
    end
    (t % (expected * 10)).should != 0
  end
end
