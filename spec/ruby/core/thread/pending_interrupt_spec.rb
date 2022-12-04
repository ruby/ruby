require_relative '../../spec_helper'

describe "Thread.pending_interrupt?" do
  it "returns false if there are no pending interrupts, e.g., outside any Thread.handle_interrupt block" do
    Thread.pending_interrupt?.should == false
  end

  it "returns true if there are pending interrupts, e.g., Thread#raise inside Thread.handle_interrupt" do
    executed = false
    -> {
      Thread.handle_interrupt(RuntimeError => :never) do
        Thread.pending_interrupt?.should == false

        current = Thread.current
        Thread.new {
          current.raise "interrupt"
        }.join

        Thread.pending_interrupt?.should == true
        executed = true
      end
    }.should raise_error(RuntimeError, "interrupt")
    executed.should == true
    Thread.pending_interrupt?.should == false
  end
end

describe "Thread#pending_interrupt?" do
  it "returns whether the given threads has pending interrupts" do
    Thread.current.pending_interrupt?.should == false
  end
end
