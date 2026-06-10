require_relative '../../../spec_helper'
require 'digest'

describe "Digest::SHA256#update" do
  it "is an alias of Digest::SHA256#<<" do
    Digest::SHA256.instance_method(:update).should == Digest::SHA256.instance_method(:<<)
  end
end
