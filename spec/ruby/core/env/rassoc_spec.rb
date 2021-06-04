require_relative '../../spec_helper'

describe "ENV.rassoc" do
  before :each do
    @foo = ENV["foo"]
    @baz = ENV["baz"]
  end

  after :each do
    ENV["foo"] = @foo
    ENV["baz"] = @baz
  end

  it "returns an array of the key and value of the environment variable with the given value" do
    ENV["foo"] = "bar"
    ENV.rassoc("bar").should == ["foo", "bar"]
  end

  it "returns a single array even if there are multiple such environment variables" do
    ENV["foo"] = "bar"
    ENV["baz"] = "bar"
    [
        ["foo", "bar"],
        ["baz", "bar"],
    ].should include(ENV.rassoc("bar"))
  end

  it "returns nil if no environment variable with the given value exists" do
    ENV.rassoc("bar").should == nil
  end

  it "returns the value element coerced with #to_str" do
    ENV["foo"] = "bar"
    v = mock('value')
    v.should_receive(:to_str).and_return("bar")
    ENV.rassoc(v).should == ["foo", "bar"]
  end

  it "returns nil if the argument is not a String and does not respond to #to_str" do
    ENV.rassoc(Object.new).should == nil
  end
end
