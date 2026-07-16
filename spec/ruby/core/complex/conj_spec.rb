require_relative '../../spec_helper'

describe "Complex#conj" do
  it "is an alias of Complex#conjugate" do
    Complex.instance_method(:conj).should == Complex.instance_method(:conjugate)
  end
end
