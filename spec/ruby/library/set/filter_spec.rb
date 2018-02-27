require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)

ruby_version_is "2.6" do
  describe "Set#filter!" do
    it_behaves_like :set_select_bang, :filter!
  end
end
