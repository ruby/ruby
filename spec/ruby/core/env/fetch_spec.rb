require_relative '../../spec_helper'
require_relative '../../shared/hash/key_error'

describe "ENV.fetch" do
  before :each do
    @foo_saved = ENV.delete("foo")
  end
  after :each do
    ENV["foo"] = @saved_foo
  end

  it "returns a value" do
    ENV["foo"] = "bar"
    ENV.fetch("foo").should == "bar"
  end

  it "raises a TypeError if the key is not a String" do
    -> { ENV.fetch Object.new }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  context "when the key is not found" do
    it_behaves_like :key_error, -> obj, key { obj.fetch(key) }, ENV

    it "formats the object with #inspect in the KeyError message" do
      -> {
        ENV.fetch('foo')
      }.should raise_error(KeyError, 'key not found: "foo"')
    end
  end

  it "provides the given default parameter" do
    ENV.fetch("foo", "default").should == "default"
  end

  it "does not insist that the default be a String" do
    ENV.fetch("foo", :default).should == :default
  end

  it "provides a default value from a block" do
    ENV.fetch("foo") { |k| "wanted #{k}" }.should == "wanted foo"
  end

  it "does not insist that the block return a String" do
    ENV.fetch("foo") { |k| k.to_sym }.should == :foo
  end

  it "warns on block and default parameter given" do
    -> do
       ENV.fetch("foo", "default") { "bar" }.should == "bar"
    end.should complain(/block supersedes default value argument/)
  end

  it "does not evaluate the block when key found" do
    ENV["foo"] = "bar"
    ENV.fetch("foo") { fail "should not get here"}.should == "bar"
  end

  it "uses the locale encoding" do
    ENV["foo"] = "bar"
    ENV.fetch("foo").encoding.should == Encoding.find('locale')
  end
end
