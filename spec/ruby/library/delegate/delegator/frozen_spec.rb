require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "Delegator when frozen" do
  before :all do
    @array = [42, :hello]
    @delegate = DelegateSpecs::Delegator.new(@array)
    @delegate.freeze
  end

  it "is still readable" do
    @delegate.should == [42, :hello]
    @delegate.include?("bar").should == false
  end

  it "is frozen" do
    @delegate.frozen?.should == true
  end

  it "is not writable" do
    ->{ @delegate[0] += 2 }.should.raise( RuntimeError )
  end

  it "creates a frozen clone" do
    @delegate.clone.frozen?.should == true
  end

  it "creates an unfrozen dup" do
    @delegate.dup.frozen?.should == false
  end

  it "causes mutative calls to raise RuntimeError" do
    ->{ @delegate.__setobj__("hola!") }.should.raise( RuntimeError )
  end

  it "returns false if only the delegated object is frozen" do
    DelegateSpecs::Delegator.new([1,2,3].freeze).frozen?.should == false
  end
end
