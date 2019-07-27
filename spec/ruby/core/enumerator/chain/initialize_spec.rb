require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::Chain#initialize" do
    before :each do
      @uninitialized = Enumerator::Chain.allocate
    end

    it "is a private method" do
      Enumerator::Chain.should have_private_instance_method(:initialize, false)
    end

    it "returns self" do
      @uninitialized.send(:initialize).should equal(@uninitialized)
    end

    it "accepts many arguments" do
      @uninitialized.send(:initialize, 0..1, 2..3, 4..5).should equal(@uninitialized)
    end

    it "accepts arguments that are not Enumerable nor responding to :each" do
      @uninitialized.send(:initialize, Object.new).should equal(@uninitialized)
    end

    describe "on frozen instance" do
      it "raises a RuntimeError" do
        -> {
          @uninitialized.freeze.send(:initialize)
        }.should raise_error(RuntimeError)
      end
    end
  end
end
