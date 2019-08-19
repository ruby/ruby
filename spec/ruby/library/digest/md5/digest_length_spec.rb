require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::MD5#digest_length" do

  it "returns the length of computed digests" do
    cur_digest = Digest::MD5.new
    cur_digest.digest_length.should == MD5Constants::DigestLength
  end

end
