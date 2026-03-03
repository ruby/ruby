require_relative '../../spec_helper'
require_relative '../../shared/hash/key_error'
require_relative 'fixtures/common'

ruby_version_is "4.1" do
  describe "ENV.fetch_values" do
    before :each do
      @saved_foo = ENV["foo"]
      @saved_bar = ENV["bar"]
      @saved_baz = ENV["baz"]
    end

    after :each do
      ENV["foo"] = @saved_foo
      ENV["bar"] = @saved_bar
      ENV["baz"] = @saved_baz
    end

    describe "with matched keys" do
      it "returns the values for the given keys" do
        ENV["foo"] = "oof"
        ENV["bar"] = "rab"
        ENV.fetch_values("foo", "bar").should == ["oof", "rab"]
      end

      it "returns the values in the order of the requested keys" do
        ENV["foo"] = "oof"
        ENV["bar"] = "rab"
        ENV.fetch_values("bar", "foo").should == ["rab", "oof"]
      end
    end

    describe "with unmatched keys" do
      it_behaves_like :key_error, -> obj, key { obj.fetch_values(key) }, ENV

      it "raises KeyError with the key name as the message" do
        ENV.delete("bar")
        -> {
          ENV.fetch_values("bar")
        }.should raise_error(KeyError, 'key not found: "bar"')
      end

      it "returns the default value from block" do
        ENV["foo"] = "oof"
        ENV.delete("bar")
        ENV.fetch_values("bar") { |key| "default_#{key}" }.should == ["default_bar"]
        ENV.fetch_values("foo", "bar") { |key| "default_#{key}" }.should == ["oof", "default_bar"]
      end
    end

    describe "without keys" do
      it "returns an empty Array" do
        ENV.fetch_values.should == []
      end
    end

    it "raises TypeError when a key is not coercible to String" do
      -> { ENV.fetch_values(Object.new) }.should raise_error(TypeError, "no implicit conversion of Object into String")
    end

    it "uses the locale encoding" do
      ENV["foo"] = "bar"
      ENV.fetch_values("foo").first.encoding.should == ENVSpecs.encoding
    end
  end
end
