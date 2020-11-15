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

    it "uses #each_entry on the provided Enumerable" do
      enumerable = MockObject.new('mock-enumerable')
      enumerable.should_receive(:each_entry).and_yield(1).and_yield(2).and_yield(3)
      q = Queue.new(enumerable)
      q.size.should == 3
      q.should_not.empty?
      q.pop.should == 1
      q.pop.should == 2
      q.pop.should == 3
      q.should.empty?
    end
    it "uses #each on the provided Enumerable if it does not respond to #each_entry" do
      enumerable = MockObject.new('mock-enumerable')
      enumerable.should_receive(:each).and_yield(1).and_yield(2).and_yield(3)
      q = Queue.new(enumerable)
      q.size.should == 3
      q.should_not.empty?
      q.pop.should == 1
      q.pop.should == 2
      q.pop.should == 3
      q.should.empty?
    end

    it "raises if the provided Enumerable does not respond to #each_entry or #each" do
      enumerable = MockObject.new('mock-enumerable')
      -> { Queue.new(enumerable) }.should raise_error(ArgumentError, "value must be enumerable")
    end
  end
end
