require_relative '../../../spec_helper'
require_relative 'shared/select'
require 'set'

ruby_version_is "2.6" do
  describe "SortedSet#filter!" do
    it_behaves_like :sorted_set_select_bang, :filter!
  end
end
