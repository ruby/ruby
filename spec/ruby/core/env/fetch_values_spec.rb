require_relative '../../spec_helper'
require_relative 'fixtures/common'

ruby_version_is "4.1" do
  describe "ENV.fetch_values" do
    before :each do
      @saved_foo = ENV["foo"]
      @saved_bar = ENV["bar"]
      ENV.delete("foo")
      ENV.delete("bar")
    end

    after :each do
      ENV["foo"] = @saved_foo
      ENV["bar"] = @saved_bar
    end

    it "returns an array of the values corresponding to the given keys" do
      ENV["foo"] = "oof"
      ENV["bar"] = "rab"
      ENV.fetch_values("bar", "foo").should == ["rab", "oof"]
    end

    it "returns the default value from block" do
      ENV["foo"] = "oof"
      ENV.fetch_values("bar") { |key| "`#{key}' is not found" }.should == ["`bar' is not found"]
      ENV.fetch_values("bar", "foo") { |key| "`#{key}' is not found" }.should == ["`bar' is not found", "oof"]
    end

    it "returns an empty array if no keys specified" do
      ENV.fetch_values.should == []
    end

    it "raises KeyError when there is no matching key" do
      ENV["foo"] = "oof"
      ENV["bar"] = "rab"
      -> {
        ENV.fetch_values("bar", "y", "foo", "z")
      }.should raise_error(KeyError, 'key not found: "y"')
    end

    it "uses the locale encoding" do
      ENV.fetch_values(ENV.keys.first).first.encoding.should == ENVSpecs.encoding
    end

    it "raises TypeError when a key is not coercible to String" do
      ENV["foo"] = "oof"
      -> { ENV.fetch_values("foo", Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
    end
  end
end
