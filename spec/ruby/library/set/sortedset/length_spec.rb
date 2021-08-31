require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/length'
  require 'set'

  describe "SortedSet#length" do
    it_behaves_like :sorted_set_length, :length
  end
end
