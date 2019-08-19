require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA256#digest_length" do

  it "returns the length of computed digests" do
    cur_digest = Digest::SHA256.new
    cur_digest.digest_length.should == SHA256Constants::DigestLength
  end

end
