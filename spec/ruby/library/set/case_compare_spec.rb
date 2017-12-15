require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/include', __FILE__)
require 'set'

ruby_version_is "2.5" do
  describe "Set#===" do
    it_behaves_like :set_include, :===

    it "is an alias for include?" do
      set = Set.new
      set.method(:===).should == set.method(:include?)
    end
  end
end

