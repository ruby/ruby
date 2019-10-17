require_relative '../../spec_helper'
require_relative 'shared/select'

ruby_version_is "2.6" do
  describe "Hash#filter" do
    it_behaves_like :hash_select, :filter
  end

  describe "Hash#filter!" do
    it_behaves_like :hash_select!, :filter!
  end
end
