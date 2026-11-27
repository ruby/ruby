require_relative '../../../spec_helper'

describe "Enumerator::Lazy#filter" do
  it "is an alias of Enumerator::Lazy#select" do
    Enumerator::Lazy.instance_method(:filter).should ==
      Enumerator::Lazy.instance_method(:select)
  end
end
