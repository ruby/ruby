require_relative '../../../../spec_helper'
require 'net/http'

describe "Net::HTTP#use_ssl?" do
  it "returns false" do
    http = Net::HTTP.new("localhost")
    http.use_ssl?.should be_false
  end
end
