require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA384#reset" do

  it "returns digest state to initial conditions" do
    cur_digest = Digest::SHA384.new
    cur_digest.update SHA384Constants::Contents
    cur_digest.digest().should_not == SHA384Constants::BlankDigest
    cur_digest.reset
    cur_digest.digest().should == SHA384Constants::BlankDigest
  end

end
