require_relative '../../spec_helper'

describe "Symbol#to_sym" do
  it "returns self" do
    [:rubinius, :squash, :[], :@ruby, :@@ruby].each do |sym|
      sym.to_sym.should == sym
    end
  end
end
