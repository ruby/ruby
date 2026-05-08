require_relative '../../spec_helper'
require_relative '../../shared/kernel/equal'

describe "BasicObject#==" do
  it "is a public instance method" do
    BasicObject.public_instance_methods(false).should.include?(:==)
  end

  it_behaves_like :object_equal, :==
end
