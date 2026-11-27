require_relative '../../../spec_helper'
require 'net/http'

describe "Net::HTTP.is_version_1_2?" do
  it "is an alias of Net::HTTP.version_1_2?" do
    Net::HTTP.method(:is_version_1_2?).should == Net::HTTP.method(:version_1_2?)
  end
end
