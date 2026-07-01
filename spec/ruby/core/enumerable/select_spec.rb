require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumerable_enumeratorized'

describe "Enumerable#select" do
  before :each do
    ScratchPad.record []
    @elements = (1..10).to_a
    @numerous = EnumerableSpecs::Numerous.new(*@elements)
  end

  it "returns all elements for which the block is not false" do
    @numerous.select {|i| i % 3 == 0 }.should == [3, 6, 9]
    @numerous.select {|i| true }.should == @elements
    @numerous.select {|i| false }.should == []
  end

  it "returns an enumerator when no block given" do
    @numerous.select.should.instance_of?(Enumerator)
  end

  it "passes through the values yielded by #each_with_index" do
    [:a, :b].each_with_index.select { |x, i| ScratchPad << [x, i] }
    ScratchPad.recorded.should == [[:a, 0], [:b, 1]]
  end

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.select {|e| e == [3, 4, 5] }.should == [[3, 4, 5]]
  end

  it_behaves_like :enumerable_enumeratorized_with_origin_size, :select
end
