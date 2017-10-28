require File.expand_path('../../fixtures/classes', __FILE__)

describe :time_now, shared: true do
  it "creates a subclass instance if called on a subclass" do
    TimeSpecs::SubTime.send(@method).should be_an_instance_of(TimeSpecs::SubTime)
    TimeSpecs::MethodHolder.send(@method).should be_an_instance_of(Time)
  end

  it "sets the current time" do
    now = TimeSpecs::MethodHolder.send(@method)
    now.to_f.should be_close(Process.clock_gettime(Process::CLOCK_REALTIME), 10.0)
  end

  it "uses the local timezone" do
    with_timezone("PDT", -8) do
      now = TimeSpecs::MethodHolder.send(@method)
      now.utc_offset.should == (-8 * 60 * 60)
    end
  end
end
