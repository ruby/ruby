require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#to_s" do

  it "returns a hexdigest" do
    cur_digest = Digest::SHA384.new
    cur_digest.to_s.should == SHA384Constants::BlankHexdigest
  end

  it "does not change the internal state" do
    cur_digest = Digest::SHA384.new
    cur_digest.to_s.should == SHA384Constants::BlankHexdigest
    cur_digest.to_s.should == SHA384Constants::BlankHexdigest

    cur_digest << SHA384Constants::Contents
    cur_digest.to_s.should == SHA384Constants::Hexdigest
    cur_digest.to_s.should == SHA384Constants::Hexdigest
  end

end
