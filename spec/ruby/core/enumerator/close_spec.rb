require_relative '../../spec_helper'

describe "Enumerator#close" do
  it "returns nil" do
    3.times.close.should == nil
  end

  it "can be called more than once" do
    enumerator = 3.times
    enumerator.close.should == nil
    enumerator.close.should == nil
  end

  it "causes further iteration to raise Enumerator::ClosedError" do
    enumerator = 3.times
    enumerator.close

    -> { enumerator.each {} }.should.raise(Enumerator::ClosedError)
    -> { enumerator.each }.should.raise(Enumerator::ClosedError)
    -> { enumerator.next }.should.raise(Enumerator::ClosedError)
    -> { enumerator.peek }.should.raise(Enumerator::ClosedError)
    -> { enumerator.next_values }.should.raise(Enumerator::ClosedError)
    -> { enumerator.peek_values }.should.raise(Enumerator::ClosedError)
    -> { enumerator.feed(:value) }.should.raise(Enumerator::ClosedError)
    -> { enumerator.rewind }.should.raise(Enumerator::ClosedError)
  end

  it "releases the external iteration fiber" do
    finalized = false
    enumerator = Enumerator.new do |y|
      begin
        y << :ok
      ensure
        finalized = true
      end
    end

    enumerator.next.should == :ok
    enumerator.close
    finalized.should == true
  end
end

