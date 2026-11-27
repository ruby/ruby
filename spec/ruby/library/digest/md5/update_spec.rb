require_relative '../../../spec_helper'
require 'digest'

describe "Digest::MD5#update" do
  it "is an alias of Digest::MD5#<<" do
    Digest::MD5.instance_method(:update).should == Digest::MD5.instance_method(:<<)
  end
end
