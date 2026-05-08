# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'

describe "Enumerator::Yielder#initialize" do
  before :each do
    @class = Enumerator::Yielder
    @uninitialized = @class.allocate
  end

  it "is a private method" do
    @class.private_instance_methods(false).should.include?(:initialize)
  end

  it "returns self when given a block" do
    @uninitialized.send(:initialize) {}.should.equal?(@uninitialized)
  end
end
