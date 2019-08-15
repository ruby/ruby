require_relative '../../spec_helper'
require_relative '../../shared/kernel/equal'

describe "Kernel#eql?" do
  it "is a public instance method" do
    Kernel.should have_public_instance_method(:eql?)
  end

  it_behaves_like :object_equal, :eql?
end
