require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)
require 'set'

ruby_version_is "2.6" do
  describe "SortedSet#filter!" do
    it_behaves_like :sorted_set_select_bang, :filter!
  end
end
