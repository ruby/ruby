require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA256#digest!" do

  it "returns a digest and can digest!" do
    cur_digest = Digest::SHA256.new
    cur_digest << SHA256Constants::Contents
    cur_digest.digest!().should == SHA256Constants::Digest
    cur_digest.digest().should == SHA256Constants::BlankDigest
  end

end
