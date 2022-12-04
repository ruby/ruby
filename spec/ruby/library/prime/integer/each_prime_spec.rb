require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'prime'

  describe "Integer.each_prime" do
    it "is transferred to Prime.each" do
      Prime.should_receive(:each).with(100).and_yield(2).and_yield(3).and_yield(5)
      yielded = []
      Integer.each_prime(100) do |prime|
        yielded << prime
      end
      yielded.should == [2,3,5]
    end
  end
end
