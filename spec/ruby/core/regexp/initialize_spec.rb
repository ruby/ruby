require_relative '../../spec_helper'

describe "Regexp#initialize" do
  it "is a private method" do
    Regexp.private_instance_methods(false).should.include?(:initialize)
  end

  it "raises a FrozenError on a Regexp literal" do
    -> { //.send(:initialize, "") }.should.raise(FrozenError)
  end

  ruby_version_is "4.1" do
    it "raises a FrozenError on an initialized non-literal Regexp" do
      regexp = Regexp.new("")
      -> { regexp.send(:initialize, "") }.should.raise(FrozenError)
    end
  end

  ruby_version_is ""..."4.1" do
    it "raises a TypeError on an initialized non-literal Regexp" do
      -> { Regexp.new("").send(:initialize, "") }.should.raise(TypeError)
    end
  end

  it "raises a TypeError on an initialized non-literal Regexp subclass" do
    r = Class.new(Regexp).new("")
    -> { r.send(:initialize, "") }.should.raise(TypeError)
  end
end
