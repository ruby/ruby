require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#length" do
  it "returns the length of the digest" do
    cur_digest = Digest::SHA384.new
    cur_digest.length.should == SHA384Constants::BlankDigest.size
    cur_digest << SHA384Constants::Contents
    cur_digest.length.should == SHA384Constants::Digest.size
  end
end
