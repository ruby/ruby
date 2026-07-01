require_relative '../../../spec_helper'

describe "Enumerator::Chain#initialize" do
  before :each do
    @uninitialized = Enumerator::Chain.allocate
  end

  it "is a private method" do
    Enumerator::Chain.private_instance_methods(false).should.include?(:initialize)
  end

  it "returns self" do
    @uninitialized.send(:initialize).should.equal?(@uninitialized)
  end

  it "accepts many arguments" do
    @uninitialized.send(:initialize, 0..1, 2..3, 4..5).should.equal?(@uninitialized)
  end

  it "accepts arguments that are not Enumerable nor responding to :each" do
    @uninitialized.send(:initialize, Object.new).should.equal?(@uninitialized)
  end

  describe "on frozen instance" do
    it "raises a FrozenError" do
      -> {
        @uninitialized.freeze.send(:initialize)
      }.should.raise(FrozenError)
    end
  end
end
