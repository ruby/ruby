require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.6" do
  describe "Enumerable#chain" do
    before :each do
      ScratchPad.record []
    end

    it "returns a chain of self and provided enumerables" do
      one = EnumerableSpecs::Numerous.new(1)
      two = EnumerableSpecs::Numerous.new(2)
      three = EnumerableSpecs::Numerous.new(3)

      chain = one.chain(two, three)

      chain.should be_an_instance_of(Enumerator::Chain)
      chain.each { |item| ScratchPad << item }
      ScratchPad.recorded.should == [1, 2, 3]
    end
  end
end
