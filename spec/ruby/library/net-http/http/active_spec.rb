require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#active?" do
  it "is an alias of Net::HTTP#started?" do
    Net::HTTP.instance_method(:active?).should == Net::HTTP.instance_method(:started?)
  end
end
