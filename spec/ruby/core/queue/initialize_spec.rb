require_relative '../../spec_helper'

describe "Queue#initialize" do
  it "can be passed no arguments for an empty Queue" do
    q = Queue.new
    q.size.should == 0
    q.should.empty?
  end

  ruby_version_is '3.1' do
    it "adds all elements of the passed Enumerable to self" do
      q = Queue.new([1, 2, 3])
      q.size.should == 3
      q.should_not.empty?
      q.pop.should == 1
      q.pop.should == 2
      q.pop.should == 3
      q.should.empty?
    end

    it "uses #to_ary on the provided Enumerable" do
      enumerable = MockObject.new('mock-enumerable')
      enumerable.should_receive(:to_ary).and_return([1, 2, 3])
      q = Queue.new(enumerable)
      q.size.should == 3
      q.should_not.empty?
      q.pop.should == 1
      q.pop.should == 2
      q.pop.should == 3
      q.should.empty?
    end

    it "raises if the provided Enumerable does not respond to #to_ary" do
      enumerable = MockObject.new('mock-enumerable')
      -> { Queue.new(enumerable) }.should raise_error(TypeError, "no implicit conversion of MockObject into Array")
    end

    it "raises if the provided Enumerable #to_ary does not return an Array" do
      enumerable = MockObject.new('mock-enumerable')
      enumerable.should_receive(:to_ary).and_return(14)
      -> { Queue.new(enumerable) }.should raise_error(TypeError, "can't convert MockObject to Array (MockObject#to_ary gives Integer)")
    end
  end
end
