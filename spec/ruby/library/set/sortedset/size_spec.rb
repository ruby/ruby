require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/length'
  require 'set'

  describe "SortedSet#size" do
    it_behaves_like :sorted_set_length, :size
  end
end
