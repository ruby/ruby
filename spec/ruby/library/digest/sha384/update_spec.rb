require_relative '../../../spec_helper'
require 'digest'

describe "Digest::SHA384#update" do
  it "is an alias of Digest::SHA384#<<" do
    Digest::SHA384.instance_method(:update).should == Digest::SHA384.instance_method(:<<)
  end
end
