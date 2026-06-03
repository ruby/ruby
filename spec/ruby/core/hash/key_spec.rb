require_relative '../../spec_helper'

describe "Hash#key?" do
  it "is an alias of Hash#include?" do
    Hash.instance_method(:key?).should == Hash.instance_method(:include?)
  end
end

describe "Hash#key" do
  it "returns the corresponding key for value" do
    { 2 => 'a', 1 => 'b' }.key('b').should == 1
  end

  it "returns nil if the value is not found" do
    { a: -1, b: 3.14, c: 2.718 }.key(1).should == nil
  end

  it "doesn't return default value if the value is not found" do
    Hash.new(5).key(5).should == nil
  end

  it "compares values using ==" do
    { 1 => 0 }.key(0.0).should == 1
    { 1 => 0.0 }.key(0).should == 1

    needle = mock('needle')
    inhash = mock('inhash')
    inhash.should_receive(:==).with(needle).and_return(true)

    { 1 => inhash }.key(needle).should == 1
  end
end
