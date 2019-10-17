require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#hexdigest!" do

  it "returns a hexdigest and resets the state" do
    cur_digest = Digest::SHA512.new

    cur_digest << SHA512Constants::Contents
    cur_digest.hexdigest!.should == SHA512Constants::Hexdigest
    cur_digest.hexdigest.should == SHA512Constants::BlankHexdigest
  end

end
