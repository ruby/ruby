require_relative '../../spec_helper'

describe "ObjectSpace::WeakMap" do

  # Note that we can't really spec the most important aspect of this class: that entries get removed when the values
  # become unreachable. This is because Ruby does not offer a way to reliable invoke GC (GC.start is not enough, neither
  # on MRI or on alternative implementations).

  it "includes Enumerable" do
    ObjectSpace::WeakMap.include?(Enumerable).should == true
  end
end
