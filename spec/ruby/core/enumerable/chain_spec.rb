require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.6" do
  describe "Enumerable#chain" do
    before :each do
      ScratchPad.record []
    end

    it "returns a chain of self and provided enumerables" do
      one = EnumerableSpecs::Numerous.new(1)
      two = EnumerableSpecs::Numerous.new(2, 3)
      three = EnumerableSpecs::Numerous.new(4, 5, 6)

      chain = one.chain(two, three)

      chain.each { |item| ScratchPad << item }
      ScratchPad.recorded.should == [1, 2, 3, 4, 5, 6]
    end

    it "returns an Enumerator::Chain if given a block" do
      EnumerableSpecs::Numerous.new.chain.should be_an_instance_of(Enumerator::Chain)
    end
  end
end
