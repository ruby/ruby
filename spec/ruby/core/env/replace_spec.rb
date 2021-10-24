require_relative '../../spec_helper'

describe "ENV.replace" do
  before :each do
    @orig = ENV.to_hash
    ENV.delete("foo")
  end

  after :each do
    ENV.replace(@orig)
  end

  it "replaces ENV with a Hash" do
    ENV.replace("foo" => "0", "bar" => "1").should equal(ENV)
    ENV.size.should == 2
    ENV["foo"].should == "0"
    ENV["bar"].should == "1"
  end

  it "raises TypeError if the argument is not a Hash" do
    -> { ENV.replace(Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into Hash")
    ENV.to_hash.should == @orig
  end

  it "raises TypeError if a key is not a String" do
    -> { ENV.replace(Object.new => "0") }.should raise_error(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end

  it "raises TypeError if a value is not a String" do
    -> { ENV.replace("foo" => Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end

  it "raises Errno::EINVAL when the key contains the '=' character" do
    -> { ENV.replace("foo=" =>"bar") }.should raise_error(Errno::EINVAL)
  end

  it "raises Errno::EINVAL when the key is an empty string" do
    -> { ENV.replace("" => "bar") }.should raise_error(Errno::EINVAL)
  end

  it "does not accept good data preceding an error" do
    -> { ENV.replace("foo" => "1", Object.new => Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  it "does not accept good data following an error" do
    -> { ENV.replace(Object.new => Object.new, "foo" => "0") }.should raise_error(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end
end
