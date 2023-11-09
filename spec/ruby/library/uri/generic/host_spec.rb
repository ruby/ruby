require_relative '../../../spec_helper'
require 'uri'

describe "URI::Generic#host" do
  version_is URI::VERSION, "0.12" do #ruby_version_is "3.2" do
    # https://hackerone.com/reports/156615
    it "returns empty string when host is empty" do
      URI.parse('http:////foo.com').host.should == ''
    end
  end
end

describe "URI::Generic#host=" do
  it "needs to be reviewed for spec completeness"
end
