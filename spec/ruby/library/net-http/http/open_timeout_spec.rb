require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP#open_timeout" do
  it "returns the seconds to wait till the connection is open" do
    net = Net::HTTP.new("localhost")
    net.open_timeout.should eql(60)
    net.open_timeout = 10
    net.open_timeout.should eql(10)
  end
end

describe "Net::HTTP#open_timeout=" do
  it "sets the seconds to wait till the connection is open" do
    net = Net::HTTP.new("localhost")
    net.open_timeout = 10
    net.open_timeout.should eql(10)
  end

  it "returns the newly set value" do
    net = Net::HTTP.new("localhost")
    (net.open_timeout = 10).should eql(10)
  end
end
