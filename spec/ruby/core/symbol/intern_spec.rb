require_relative '../../spec_helper'

describe "Symbol#intern" do
  it "returns self" do
    :foo.intern.should == :foo
  end

  it "returns a Symbol" do
    :foo.intern.should be_kind_of(Symbol)
  end
end
