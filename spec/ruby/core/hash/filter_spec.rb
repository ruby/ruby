require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)

ruby_version_is "2.6" do
  describe "Hash#filter" do
    it_behaves_like :hash_select, :filter
  end

  describe "Hash#filter!" do
    it_behaves_like :hash_select!, :filter!
  end
end
