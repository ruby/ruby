require_relative '../../../spec_helper'

describe "Enumerator::Lazy#find_all" do
  it "is an alias of Enumerator::Lazy#select" do
    Enumerator::Lazy.instance_method(:find_all).should ==
      Enumerator::Lazy.instance_method(:select)
  end
end
