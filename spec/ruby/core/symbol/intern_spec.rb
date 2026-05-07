require_relative '../../spec_helper'

describe "Symbol#intern" do
  it "returns self" do
    :foo.intern.should == :foo
  end

  it "returns a Symbol" do
    :foo.intern.should.is_a?(Symbol)
  end
end
