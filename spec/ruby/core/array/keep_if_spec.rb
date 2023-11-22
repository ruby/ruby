require_relative '../../spec_helper'
require_relative 'shared/keep_if'

describe "Array#keep_if" do
  it "returns the same array if no changes were made" do
    array = [1, 2, 3]
    array.keep_if { true }.should equal(array)
  end

  it_behaves_like :keep_if, :keep_if
end
