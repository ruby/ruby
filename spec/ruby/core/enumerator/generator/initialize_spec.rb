# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'

describe "Enumerator::Generator#initialize" do
  before :each do
    @class = Enumerator::Generator
    @uninitialized = @class.allocate
  end

  it "is a private method" do
    @class.private_instance_methods(false).should.include?(:initialize)
  end

  it "returns self when given a block" do
    @uninitialized.send(:initialize) {}.should.equal?(@uninitialized)
  end

  describe "on frozen instance" do
    it "raises a FrozenError" do
      -> {
        @uninitialized.freeze.send(:initialize) {}
      }.should.raise(FrozenError)
    end
  end
end
