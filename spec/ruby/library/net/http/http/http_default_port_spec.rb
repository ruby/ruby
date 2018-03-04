require_relative '../../../../spec_helper'
require 'net/http'

describe "Net::HTTP.http_default_port" do
  it "returns 80" do
    Net::HTTP.http_default_port.should eql(80)
  end
end
