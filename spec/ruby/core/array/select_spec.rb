require_relative '../../spec_helper'
require_relative 'shared/select'

describe "Array#select" do
  it_behaves_like :array_select, :select
end

describe "Array#select!" do
  it "returns nil if no changes were made in the array" do
    [1, 2, 3].select! { true }.should be_nil
  end

  it_behaves_like :keep_if, :select!
end
