require_relative '../../spec_helper'

describe "Signal.signame" do
  it "takes a signal name with a well known signal number" do
    Signal.signame(0).should == "EXIT"
  end

  it "returns nil if the argument is an invalid signal number" do
    Signal.signame(-1).should == nil
  end

  it "calls #to_int on an object to convert to an Integer" do
    obj = mock('signal')
    obj.should_receive(:to_int).and_return(0)
    Signal.signame(obj).should == "EXIT"
  end

  it "raises a TypeError when the passed argument can't be coerced to Integer" do
    -> { Signal.signame("hello") }.should raise_error(TypeError)
  end

  it "raises a TypeError when the passed argument responds to #to_int but does not return an Integer" do
    obj = mock('signal')
    obj.should_receive(:to_int).and_return('not an int')
    -> { Signal.signame(obj) }.should raise_error(TypeError)
  end

  platform_is_not :windows do
    it "the original should take precedence over alias when looked up by number" do
      Signal.signame(Signal.list["ABRT"]).should == "ABRT"
      Signal.signame(Signal.list["CHLD"]).should == "CHLD"
    end
  end
end
