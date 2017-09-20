require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../shared/include', __FILE__)
require 'set'

ruby_version_is "2.5" do
  describe "SortedSet#===" do
    it_behaves_like :sorted_set_include, :===
  end
end
