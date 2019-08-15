require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#digest!" do

  it "returns a digest and can digest!" do
    cur_digest = Digest::SHA384.new
    cur_digest << SHA384Constants::Contents
    cur_digest.digest!().should == SHA384Constants::Digest
    cur_digest.digest().should == SHA384Constants::BlankDigest
  end

end
