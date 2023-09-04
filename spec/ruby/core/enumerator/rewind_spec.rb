require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Enumerator#rewind" do
  before :each do
    @enum = 1.upto(3)
  end

  it "resets the enumerator to its initial state" do
    @enum.next.should == 1
    @enum.next.should == 2
    @enum.rewind
    @enum.next.should == 1
  end

  it "returns self" do
    @enum.rewind.should.equal? @enum
  end

  it "has no effect on a new enumerator" do
    @enum.rewind
    @enum.next.should == 1
  end

  it "has no effect if called multiple, consecutive times" do
    @enum.next.should == 1
    @enum.rewind
    @enum.rewind
    @enum.next.should == 1
  end

  it "works with peek to reset the position" do
    @enum.next
    @enum.next
    @enum.rewind
    @enum.next
    @enum.peek.should == 2
  end

  it "calls the enclosed object's rewind method if one exists" do
    obj = mock('rewinder')
    enum = obj.to_enum
    obj.should_receive(:each).at_most(1)
    obj.should_receive(:rewind)
    enum.rewind
  end

  it "does nothing if the object doesn't have a #rewind method" do
    obj = mock('rewinder')
    enum = obj.to_enum
    obj.should_receive(:each).at_most(1)
    enum.rewind.should == enum
  end
end

describe "Enumerator#rewind" do
  before :each do
    ScratchPad.record []
    @enum = EnumeratorSpecs::Feed.new.to_enum(:each)
  end

  it "clears a pending #feed value" do
    @enum.next
    @enum.feed :a
    @enum.rewind
    @enum.next
    @enum.next
    ScratchPad.recorded.should == [nil]
  end
end
