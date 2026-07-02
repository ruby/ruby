require_relative '../../spec_helper'
require_relative 'shared/intersection'

describe "Set#intersection" do
  it_behaves_like :set_intersection, :intersection
end

describe "Set#&" do
  it_behaves_like :set_intersection, :&

  ruby_version_is "4.0" do
    it "retains compare_by_identity flag" do
      @set.compare_by_identity
      (@set & Set[:b, :c, :d, :e]).compare_by_identity?.should == true
      (@set & [:b, :c, :d]).compare_by_identity?.should == true
    end
  end
end
