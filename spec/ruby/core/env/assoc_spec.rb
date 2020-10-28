require_relative '../../spec_helper'

describe "ENV.assoc" do
  before :each do
    @foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @foo
  end

  it "returns an array of the key and value of the environment variable with the given key" do
    ENV["foo"] = "bar"
    ENV.assoc("foo").should == ["foo", "bar"]
  end

  it "returns nil if no environment variable with the given key exists" do
    ENV.assoc("foo").should == nil
  end

  it "returns the key element coerced with #to_str" do
    ENV["foo"] = "bar"
    k = mock('key')
    k.should_receive(:to_str).and_return("foo")
    ENV.assoc(k).should == ["foo", "bar"]
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> { ENV.assoc(Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
