require_relative '../../../spec_helper'

describe "Enumerator::Product#rewind" do
  before :each do
    @enum = Enumerator::Product.new([1, 2].each.to_enum, [:a, :b].each.to_enum)
  end

  it "resets the enumerator to its initial state" do
    @enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
    @enum.rewind
    @enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
  end

  it "returns self" do
    @enum.rewind.should.equal? @enum
  end

  it "has no effect on a new enumerator" do
    @enum.rewind
    @enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
  end

  it "has no effect if called multiple, consecutive times" do
    @enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
    @enum.rewind
    @enum.rewind
    @enum.each.to_a.should == [[1, :a], [1, :b], [2, :a], [2, :b]]
  end

  it "calls the enclosed object's rewind method if one exists" do
    obj = mock('rewinder')
    enum = Enumerator::Product.new(obj.to_enum)

    obj.should_receive(:rewind)
    enum.rewind
  end

  it "does nothing if the object doesn't have a #rewind method" do
    obj = mock('rewinder')
    enum = Enumerator::Product.new(obj.to_enum)

    enum.rewind.should == enum
  end

  it "calls a rewind method on each enumerable in direct order" do
    ScratchPad.record []

    object1 = Object.new
    def object1.rewind; ScratchPad << :object1; end

    object2 = Object.new
    def object2.rewind; ScratchPad << :object2; end

    object3 = Object.new
    def object3.rewind; ScratchPad << :object3; end

    enum = Enumerator::Product.new(object1, object2, object3)
    enum.rewind

    ScratchPad.recorded.should == [:object1, :object2, :object3]
  end
end
