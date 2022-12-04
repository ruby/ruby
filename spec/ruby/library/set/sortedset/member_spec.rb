require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require_relative 'shared/include'
  require 'set'

  describe "SortedSet#member?" do
    it_behaves_like :sorted_set_include, :member?
  end
end
