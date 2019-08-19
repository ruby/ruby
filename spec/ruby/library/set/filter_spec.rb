require_relative '../../spec_helper'
require_relative 'shared/select'

ruby_version_is "2.6" do
  describe "Set#filter!" do
    it_behaves_like :set_select_bang, :filter!
  end
end
