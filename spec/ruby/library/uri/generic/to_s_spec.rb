require_relative '../../../spec_helper'
require 'uri'

describe "URI::Generic#to_s" do
  version_is URI::VERSION, "0.12" do #ruby_version_is "3.2" do
    # https://hackerone.com/reports/156615
    it "preserves / characters when host is empty" do
      URI('http:///foo.com').to_s.should == 'http:///foo.com'
    end
  end
end
