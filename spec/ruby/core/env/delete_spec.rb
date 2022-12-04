require_relative '../../spec_helper'

describe "ENV.delete" do
  before :each do
    @saved_foo = ENV["foo"]
  end
  after :each do
    ENV["foo"] = @saved_foo
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

  it "returns nil if the named environment variable does not exist and no block given" do
    ENV.delete("foo")
    ENV.delete("foo").should == nil
  end

  it "yields the name to the given block if the named environment variable does not exist" do
    ENV.delete("foo")
    ENV.delete("foo") { |name| ScratchPad.record name }
    ScratchPad.recorded.should == "foo"
  end

  ruby_version_is "3.0" do
    it "returns the result of given block if the named environment variable does not exist" do
      ENV.delete("foo")
      ENV.delete("foo") { |name| "bar" }.should == "bar"
    end
  end

  it "does not evaluate the block if the environment variable exists" do
    ENV["foo"] = "bar"
    ENV.delete("foo") { |name| fail "Should not happen" }
    ENV["foo"].should == nil
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> { ENV.delete(Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
