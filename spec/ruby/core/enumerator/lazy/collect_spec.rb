require_relative '../../../spec_helper'

describe "Enumerator::Lazy#collect" do
  it "is an alias of Enumerator::Lazy#map" do
    Enumerator::Lazy.instance_method(:collect).should ==
      Enumerator::Lazy.instance_method(:map)
  end
end
