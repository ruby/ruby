require_relative '../../../spec_helper'
require 'digest'

describe "Digest::SHA384#size" do
  it "is an alias of Digest::SHA384#length" do
    Digest::SHA384.instance_method(:size).should == Digest::SHA384.instance_method(:length)
  end
end
