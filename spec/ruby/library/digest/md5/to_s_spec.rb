require_relative '../../../spec_helper'

require 'digest/md5'

require_relative 'shared/constants'

describe "Digest::MD5#to_s" do

  it "returns a hexdigest" do
    cur_digest = Digest::MD5.new
    cur_digest.to_s.should == MD5Constants::BlankHexdigest
  end

  it "does not change the internal state" do
    cur_digest = Digest::MD5.new
    cur_digest.to_s.should == MD5Constants::BlankHexdigest
    cur_digest.to_s.should == MD5Constants::BlankHexdigest

    cur_digest << MD5Constants::Contents
    cur_digest.to_s.should == MD5Constants::Hexdigest
    cur_digest.to_s.should == MD5Constants::Hexdigest
  end

end
