require_relative '../../../spec_helper'
require 'digest'

describe "Digest::SHA512#update" do
  it "is an alias of Digest::SHA512#<<" do
    Digest::SHA512.instance_method(:update).should == Digest::SHA512.instance_method(:<<)
  end
end
