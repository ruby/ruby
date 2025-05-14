require_relative '../../spec_helper'
require_relative 'shared/include'

describe "Set#===" do
  it_behaves_like :set_include, :===

  it "is an alias for include?" do
    set = Set.new
    set.method(:===).should == set.method(:include?)
  end
end
