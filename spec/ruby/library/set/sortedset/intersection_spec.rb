require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/intersection'
  require 'set'

  describe "SortedSet#intersection" do
    it_behaves_like :sorted_set_intersection, :intersection
  end

  describe "SortedSet#&" do
    it_behaves_like :sorted_set_intersection, :&
  end
end
