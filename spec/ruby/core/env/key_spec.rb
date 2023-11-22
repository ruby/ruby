require_relative '../../spec_helper'
require_relative 'shared/include'

describe "ENV.key?" do
  it_behaves_like :env_include, :key?
end

describe "ENV.key" do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns the index associated with the passed value" do
    ENV["foo"] = "bar"
    ENV.key("bar").should == "foo"
  end

  it "returns nil if the passed value is not found" do
    ENV.delete("foo")
    ENV.key("foo").should be_nil
  end

  it "coerces the key element with #to_str" do
    ENV["foo"] = "bar"
    k = mock('key')
    k.should_receive(:to_str).and_return("bar")
    ENV.key(k).should == "foo"
  end

  it "raises TypeError if the argument is not a String and does not respond to #to_str" do
    -> {
      ENV.key(Object.new)
    }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
