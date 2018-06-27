require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#block_length" do

  it "returns the length of digest block" do
    cur_digest = Digest::SHA512.new
    cur_digest.block_length.should == SHA512Constants::BlockLength
  end

end
