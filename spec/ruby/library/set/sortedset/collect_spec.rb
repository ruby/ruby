require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'
  require_relative 'shared/collect'

  describe "SortedSet#collect!" do
    it_behaves_like :sorted_set_collect_bang, :collect!
  end
end
