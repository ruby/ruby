require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'
  require_relative 'shared/difference'

  describe "SortedSet#difference" do
    it_behaves_like :sorted_set_difference, :difference
  end
end
