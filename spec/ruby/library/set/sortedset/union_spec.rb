require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/union'
  require 'set'

  describe "SortedSet#union" do
    it_behaves_like :sorted_set_union, :union
  end

  describe "SortedSet#|" do
    it_behaves_like :sorted_set_union, :|
  end
end
