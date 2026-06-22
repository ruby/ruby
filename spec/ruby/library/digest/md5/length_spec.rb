require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::MD5#length" do
  it "returns the length of the digest" do
    cur_digest = Digest::MD5.new
    cur_digest.length.should == MD5Constants::BlankDigest.size
    cur_digest << MD5Constants::Contents
    cur_digest.length.should == MD5Constants::Digest.size
  end
end
