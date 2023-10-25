require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'Array#intersect?' do
  ruby_version_is '3.1' do # https://bugs.ruby-lang.org/issues/15198
    describe 'when at least one element in two Arrays is the same' do
      it 'returns true' do
        [1, 2].intersect?([2, 3, 4]).should == true
        [2, 3, 4].intersect?([1, 2]).should == true
      end
    end

    describe 'when there are no elements in common between two Arrays' do
      it 'returns false' do
        [0, 1, 2].intersect?([3, 4]).should == false
        [3, 4].intersect?([0, 1, 2]).should == false
        [3, 4].intersect?([]).should == false
        [].intersect?([0, 1, 2]).should == false
      end
    end

    it "tries to convert the passed argument to an Array using #to_ary" do
      obj = mock('[1,2,3]')
      obj.should_receive(:to_ary).and_return([1, 2, 3])

      [1, 2].intersect?(obj).should == true
    end

    it "determines equivalence between elements in the sense of eql?" do
      obj1 = mock('1')
      obj2 = mock('2')
      obj1.stub!(:hash).and_return(0)
      obj2.stub!(:hash).and_return(0)
      obj1.stub!(:eql?).and_return(true)
      obj2.stub!(:eql?).and_return(true)

      [obj1].intersect?([obj2]).should == true

      obj1 = mock('3')
      obj2 = mock('4')
      obj1.stub!(:hash).and_return(0)
      obj2.stub!(:hash).and_return(0)
      obj1.stub!(:eql?).and_return(false)
      obj2.stub!(:eql?).and_return(false)

      [obj1].intersect?([obj2]).should == false
    end

    it "does not call to_ary on array subclasses" do
      [5, 6].intersect?(ArraySpecs::ToAryArray[1, 2, 5, 6]).should == true
    end

    it "properly handles an identical item even when its #eql? isn't reflexive" do
      x = mock('x')
      x.stub!(:hash).and_return(42)
      x.stub!(:eql?).and_return(false) # Stubbed for clarity and latitude in implementation; not actually sent by MRI.

      [x].intersect?([x]).should == true
    end

    it "has semantic of !(a & b).empty?" do
      [].intersect?([]).should == false
      [nil].intersect?([nil]).should == true
    end
  end
end
