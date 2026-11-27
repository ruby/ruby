require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#length" do
  it "returns the length of the digest" do
    cur_digest = Digest::SHA512.new
    cur_digest.length.should == SHA512Constants::BlankDigest.size
    cur_digest << SHA512Constants::Contents
    cur_digest.length.should == SHA512Constants::Digest.size
  end
end
