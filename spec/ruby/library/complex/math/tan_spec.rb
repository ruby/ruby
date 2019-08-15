require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/tan'

describe "Math#tan" do
  it_behaves_like :complex_math_tan, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:tan)
  end
end

describe "Math.tan" do
  it_behaves_like :complex_math_tan, :_, CMath
end
