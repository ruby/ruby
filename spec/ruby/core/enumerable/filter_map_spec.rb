require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is '2.7' do
  describe 'Enumerable#filter_map' do
    before :each do
      @numerous = EnumerableSpecs::Numerous.new(*(1..8).to_a)
    end

    it 'returns an empty array if there are no elements' do
      EnumerableSpecs::Empty.new.filter_map { true }.should == []
    end

    it 'returns an array with truthy results of passing each element to block' do
      @numerous.filter_map { |i| i * 2 if i.even? }.should == [4, 8, 12, 16]
      @numerous.filter_map { |i| i * 2 }.should == [2, 4, 6, 8, 10, 12, 14, 16]
      @numerous.filter_map { 0 }.should == [0, 0, 0, 0, 0, 0, 0, 0]
      @numerous.filter_map { false }.should == []
      @numerous.filter_map { nil }.should == []
    end

    it 'returns an enumerator when no block given' do
      @numerous.filter_map.should be_an_instance_of(Enumerator)
    end
  end
end
