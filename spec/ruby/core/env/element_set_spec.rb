require_relative '../../spec_helper'

describe "ENV.[]=" do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "sets the environment variable to the given value" do
    ENV["foo"] = "bar"
    ENV["foo"].should == "bar"
  end

  it "returns the value" do
    value = "bar"
    ENV.send(:[]=, "foo", value).should.equal?(value)
  end

  it "deletes the environment variable when the value is nil" do
    ENV["foo"] = "bar"
    ENV["foo"] = nil
    ENV.key?("foo").should == false
  end

  it "coerces the key argument with #to_str" do
    k = mock("key")
    k.should_receive(:to_str).and_return("foo")
    ENV[k] = "bar"
    ENV["foo"].should == "bar"
  end

  it "coerces the value argument with #to_str" do
    v = mock("value")
    v.should_receive(:to_str).and_return("bar")
    ENV["foo"] = v
    ENV["foo"].should == "bar"
  end

  it "raises TypeError when the key is not coercible to String" do
    -> { ENV[Object.new] = "bar" }.should.raise(TypeError, "no implicit conversion of Object into String")
  end

  it "raises TypeError when the value is not coercible to String" do
    -> { ENV["foo"] = Object.new }.should.raise(TypeError, "no implicit conversion of Object into String")
  end

  it "raises Errno::EINVAL when the key contains the '=' character" do
    -> { ENV["foo="] = "bar" }.should.raise(Errno::EINVAL)
  end

  it "raises Errno::EINVAL when the key is an empty string" do
    -> { ENV[""] = "bar" }.should.raise(Errno::EINVAL)
  end

  it "does nothing when the key is not a valid environment variable key and the value is nil" do
    ENV["foo="] = nil
    ENV.key?("foo=").should == false
  end
end
