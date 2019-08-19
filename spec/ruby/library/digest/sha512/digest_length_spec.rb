require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#digest_length" do

  it "returns the length of computed digests" do
    cur_digest = Digest::SHA512.new
    cur_digest.digest_length.should == SHA512Constants::DigestLength
  end

end
