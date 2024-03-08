require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP.socket_type" do
  it "returns BufferedIO" do
    Net::HTTP.socket_type.should == Net::BufferedIO
  end
end
