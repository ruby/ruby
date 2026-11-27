require_relative '../../../spec_helper'
require 'digest'

describe "Digest::SHA512#size" do
  it "is an alias of Digest::SHA512#length" do
    Digest::SHA512.instance_method(:size).should == Digest::SHA512.instance_method(:length)
  end
end
