require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#to_s" do

  it "returns a hexdigest" do
    cur_digest = Digest::SHA512.new
    cur_digest.to_s.should == SHA512Constants::BlankHexdigest
  end

  it "does not change the internal state" do
    cur_digest = Digest::SHA512.new
    cur_digest.to_s.should == SHA512Constants::BlankHexdigest
    cur_digest.to_s.should == SHA512Constants::BlankHexdigest

    cur_digest << SHA512Constants::Contents
    cur_digest.to_s.should == SHA512Constants::Hexdigest
    cur_digest.to_s.should == SHA512Constants::Hexdigest
  end

end
