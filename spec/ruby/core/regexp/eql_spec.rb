require_relative '../../spec_helper'

describe "Regexp#eql?" do
  it "is an alias of Regexp#==" do
    Regexp.instance_method(:eql?).should == Regexp.instance_method(:==)
  end
end
