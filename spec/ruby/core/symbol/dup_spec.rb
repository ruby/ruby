require_relative '../../spec_helper'

describe "Symbol#dup" do
  it "returns self" do
    :a_symbol.dup.should equal(:a_symbol)
  end
end
