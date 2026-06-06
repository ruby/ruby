require_relative '../../../spec_helper'

describe "Enumerator::Lazy#enum_for" do
  it "is an alias of Enumerator::Lazy#to_enum" do
    Enumerator::Lazy.instance_method(:enum_for).should ==
      Enumerator::Lazy.instance_method(:to_enum)
  end
end
