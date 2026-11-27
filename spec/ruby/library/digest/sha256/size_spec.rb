require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA256#size" do
  it "is an alias of Digest::SHA256#length" do
    Digest::SHA256.instance_method(:size).should == Digest::SHA256.instance_method(:length)
  end
end
