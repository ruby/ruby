require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'
  require_relative 'shared/add'

  describe "SortedSet#<<" do
    it_behaves_like :sorted_set_add, :<<
  end
end
