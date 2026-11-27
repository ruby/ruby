require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA256#length" do
  it "returns the length of the digest" do
    cur_digest = Digest::SHA256.new
    cur_digest.length.should == SHA256Constants::BlankDigest.size
    cur_digest << SHA256Constants::Contents
    cur_digest.length.should == SHA256Constants::Digest.size
  end
end
