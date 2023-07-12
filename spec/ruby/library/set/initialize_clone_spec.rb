require_relative '../../spec_helper'
require 'set'

describe "Set#initialize_clone" do
  # See https://bugs.ruby-lang.org/issues/14266
  it "does not freeze the new Set when called from clone(freeze: false)" do
    set1 = Set[1, 2]
    set1.freeze
    set2 = set1.clone(freeze: false)
    set1.frozen?.should == true
    set2.frozen?.should == false
    set2.add 3
    set1.should == Set[1, 2]
    set2.should == Set[1, 2, 3]
  end
end
