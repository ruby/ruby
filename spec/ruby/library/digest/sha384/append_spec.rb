require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#<<" do
  it "can update" do
    cur_digest = Digest::SHA384.new
    cur_digest << SHA384Constants::Contents
    cur_digest.digest.should == SHA384Constants::Digest
  end
end
