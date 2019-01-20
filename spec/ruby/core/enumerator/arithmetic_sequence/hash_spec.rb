require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#hash" do
    it "is based on begin, end, step and exclude_end?" do
      1.step(10).hash.should be_an_instance_of(Integer)

      1.step(10).hash.should == 1.step(10).hash
      1.step(10, 5).hash.should == 1.step(10, 5).hash

      (1..10).step.hash.should == (1..10).step.hash
      (1...10).step(8).hash.should == (1...10).step(8).hash

      # both have exclude_end? == false
      (1..10).step(100).hash.should == 1.step(10, 100).hash

      ((1..10).step.hash == (1..11).step.hash).should == false
      ((1..10).step.hash == (1...10).step.hash).should == false
      ((1..10).step.hash == (1..10).step(2).hash).should == false
    end
  end
end
