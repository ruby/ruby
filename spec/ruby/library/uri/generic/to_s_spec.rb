require_relative '../../../spec_helper'
require 'uri'

describe "URI::Generic#to_s" do
  # https://hackerone.com/reports/156615
  it "preserves / characters when host is empty" do
    URI('http:///foo.com').to_s.should == 'http:///foo.com'
  end
end
