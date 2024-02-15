require_relative '../../spec_helper'
require 'net/http'

describe "Net::HTTPHeaderSyntaxError" do
  it "is a subclass of StandardError" do
    Net::HTTPHeaderSyntaxError.should < StandardError
  end
end
