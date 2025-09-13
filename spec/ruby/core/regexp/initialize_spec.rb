require_relative '../../spec_helper'

describe "Regexp#initialize" do
  it "is a private method" do
    Regexp.should have_private_instance_method(:initialize)
  end

  it "raises a FrozenError on a Regexp literal" do
    -> { //.send(:initialize, "") }.should raise_error(FrozenError)
  end

  ruby_version_is "4.0" do
    it "raises a FrozenError on an initialized non-literal Regexp" do
      regexp = Regexp.new("")
      -> { regexp.send(:initialize, "") }.should raise_error(FrozenError)
    end
  end

  ruby_version_is ""..."4.0" do
    it "raises a TypeError on an initialized non-literal Regexp" do
      -> { Regexp.new("").send(:initialize, "") }.should raise_error(TypeError)
    end
  end
end
