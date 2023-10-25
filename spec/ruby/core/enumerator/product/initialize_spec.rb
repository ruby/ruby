require_relative '../../../spec_helper'

ruby_version_is "3.2" do
  describe "Enumerator::Product#initialize" do
    before :each do
      @uninitialized = Enumerator::Product.allocate
    end

    it "is a private method" do
      Enumerator::Product.should have_private_instance_method(:initialize, false)
    end

    it "returns self" do
      @uninitialized.send(:initialize).should equal(@uninitialized)
    end

    it "accepts many arguments" do
      @uninitialized.send(:initialize, 0..1, 2..3, 4..5).should equal(@uninitialized)
    end

    it "accepts arguments that are not Enumerable nor responding to :each_entry" do
      @uninitialized.send(:initialize, Object.new).should equal(@uninitialized)
    end

    describe "on frozen instance" do
      it "raises a FrozenError" do
        -> {
          @uninitialized.freeze.send(:initialize, 0..1)
        }.should raise_error(FrozenError)
      end
    end
  end
end
