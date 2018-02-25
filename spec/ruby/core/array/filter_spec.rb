require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)

describe "Array#filter" do
  it_behaves_like :array_select, :filter
end

describe "Array#filter!" do
  it "returns nil if no changes were made in the array" do
    [1, 2, 3].filter! { true }.should be_nil
  end

  it_behaves_like :keep_if, :filter!
end
