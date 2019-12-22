require_relative '../../spec_helper'

describe "ENV.values_at" do
  before :each do
    @saved_foo = ENV["foo"]
    @saved_bar = ENV["bar"]
  end

  after :each do
    ENV["foo"] = @saved_foo
    ENV["bar"] = @saved_bar
  end

  it "returns an array of the values corresponding to the given keys" do
    ENV["foo"] = "oof"
    ENV["bar"] = "rab"
    ENV.values_at("bar", "foo").should == ["rab", "oof"]
  end

  it "returns an empty array if no keys specified" do
    ENV.values_at.should == []
  end

  it "returns nil for each key that is not a name" do
    ENV["foo"] = "oof"
    ENV["bar"] = "rab"
    ENV.values_at("x", "bar", "y", "foo", "z").should == [nil, "rab", nil, "oof", nil]
  end

  it "uses the locale encoding" do
    ENV.values_at(ENV.keys.first).first.encoding.should == Encoding.find('locale')
  end

  it "raises TypeError when a key is not coercible to String" do
    -> { ENV.values_at("foo", Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end
end
