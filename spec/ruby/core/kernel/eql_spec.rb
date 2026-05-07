require_relative '../../spec_helper'
require_relative '../../shared/kernel/equal'

describe "Kernel#eql?" do
  it "is a public instance method" do
    Kernel.public_instance_methods(false).should.include?(:eql?)
  end

  it_behaves_like :object_equal, :eql?
end
