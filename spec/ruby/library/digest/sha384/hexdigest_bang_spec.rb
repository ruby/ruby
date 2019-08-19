require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#hexdigest!" do

  it "returns a hexdigest and resets the state" do
    cur_digest = Digest::SHA384.new

    cur_digest << SHA384Constants::Contents
    cur_digest.hexdigest!.should == SHA384Constants::Hexdigest
    cur_digest.hexdigest.should == SHA384Constants::BlankHexdigest
  end

end
