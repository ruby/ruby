require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::MD5#<<" do
  it "can update" do
    cur_digest = Digest::MD5.new
    cur_digest << MD5Constants::Contents
    cur_digest.digest.should == MD5Constants::Digest
  end
end
