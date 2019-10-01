require_relative '../../spec_helper'

describe "ENV.delete" do
  after :each do
    ENV.delete("foo")
  end

  it "removes the variable from the environment" do
    ENV["foo"] = "bar"
    ENV.delete("foo")
    ENV["foo"].should == nil
  end

  it "returns the previous value" do
    ENV["foo"] = "bar"
    ENV.delete("foo").should == "bar"
  end

  it "ignores the block if the environment variable exists" do
    ENV["foo"] = "bar"
    begin
      -> { ENV.delete("foo") { |name| fail name } }.should_not raise_error(RuntimeError)
    end
  end

  it "yields the name to the given block if the named environment variable does not exist" do
    ENV.delete("foo")
    ENV.delete("foo") { |name| ScratchPad.record name }
    ScratchPad.recorded.should == "foo"
  end

  it "returns nil if the named environment variable does not exist and block given" do
    ENV.delete("foo")
    ENV.delete("foo") { |name| name }.should == nil
  end

  it "raises TypeError if name is not a String" do
    -> { ENV.delete(1) }.should raise_error(TypeError)
  end
end
