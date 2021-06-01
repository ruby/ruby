require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/select'
  require 'set'

  describe "SortedSet#select!" do
    it_behaves_like :sorted_set_select_bang, :select!
  end
end
