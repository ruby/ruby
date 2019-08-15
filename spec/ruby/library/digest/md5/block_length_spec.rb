require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::MD5#block_length" do

  it "returns the length of digest block" do
    cur_digest = Digest::MD5.new
    cur_digest.block_length.should == MD5Constants::BlockLength
  end

end
