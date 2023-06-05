require_relative '../../spec_helper'

describe "Kernel#singleton_class" do
  it "returns class extended from an object" do
    x = Object.new
    xs = class << x; self; end
    xs.should == x.singleton_class
  end

  it "returns NilClass for nil" do
    nil.singleton_class.should == NilClass
  end

  it "returns TrueClass for true" do
    true.singleton_class.should == TrueClass
  end

  it "returns FalseClass for false" do
    false.singleton_class.should == FalseClass
  end

  it "raises TypeError for Integer" do
    -> { 123.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for Float" do
    -> { 3.14.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for Symbol" do
    -> { :foo.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for a frozen deduplicated String" do
    -> { (-"string").singleton_class }.should raise_error(TypeError, "can't define singleton")
    -> { a = -"string"; a.singleton_class }.should raise_error(TypeError, "can't define singleton")
    -> { a = "string"; (-a).singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "returns a frozen singleton class if object is frozen" do
    obj = Object.new
    obj.freeze
    obj.singleton_class.frozen?.should be_true
  end
end
