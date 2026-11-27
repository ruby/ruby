require_relative '../../spec_helper'

describe "Complex#marshal_dump" do
  it "is a private method" do
    Complex.private_instance_methods(false).should.include?(:marshal_dump)
  end

  it "dumps real and imaginary parts" do
    Complex(1, 2).send(:marshal_dump).should == [1, 2]
  end
end
