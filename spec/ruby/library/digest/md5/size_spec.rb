require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::MD5#size" do
  it "is an alias of Digest::MD5#length" do
    Digest::MD5.instance_method(:size).should == Digest::MD5.instance_method(:length)
  end
end
