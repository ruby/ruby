require_relative '../../spec_helper'
require_relative 'shared/select'

ruby_version_is "2.6" do
  describe "Array#filter" do
    it_behaves_like :array_select, :filter
  end

  describe "Array#filter!" do
    it "returns nil if no changes were made in the array" do
      [1, 2, 3].filter! { true }.should be_nil
    end

    it_behaves_like :keep_if, :filter!
  end
end
