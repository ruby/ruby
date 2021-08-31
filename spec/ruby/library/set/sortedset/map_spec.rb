require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'
  require_relative 'shared/collect'

  describe "SortedSet#map!" do
    it_behaves_like :sorted_set_collect_bang, :map!
  end
end
