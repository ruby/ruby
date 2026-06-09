require_relative '../../../spec_helper'

describe "Enumerator::Lazy#collect_concat" do
  it "is an alias of Enumerator::Lazy#flat_map" do
    Enumerator::Lazy.instance_method(:collect_concat).should ==
      Enumerator::Lazy.instance_method(:flat_map)
  end
end
