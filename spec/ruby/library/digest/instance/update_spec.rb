require_relative '../../../spec_helper'
require 'digest'

describe "Digest::Instance#update" do
  it "is an alias of Digest::Instance#<<" do
    Digest::Instance.instance_method(:update).should == Digest::Instance.instance_method(:<<)
  end
end
