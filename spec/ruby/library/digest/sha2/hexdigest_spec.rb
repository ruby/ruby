require_relative '../../../spec_helper'
require_relative '../sha256/shared/constants'

describe "Digest::SHA2#hexdigest" do

  it "returns a SHA256 hexdigest by default" do
    cur_digest = Digest::SHA2.new
    cur_digest.hexdigest.should == SHA256Constants::BlankHexdigest

    # add something to check that the state is reset later
    cur_digest << "test"

    cur_digest.hexdigest(SHA256Constants::Contents).should == SHA256Constants::Hexdigest
    # second invocation is intentional, to make sure there are no side-effects
    cur_digest.hexdigest(SHA256Constants::Contents).should == SHA256Constants::Hexdigest

    # after all is done, verify that the digest is in the original, blank state
    cur_digest.hexdigest.should == SHA256Constants::BlankHexdigest
  end

end

describe "Digest::SHA2.hexdigest" do

  it "returns a SHA256 hexdigest by default" do
    Digest::SHA2.hexdigest(SHA256Constants::Contents).should == SHA256Constants::Hexdigest
    # second invocation is intentional, to make sure there are no side-effects
    Digest::SHA2.hexdigest(SHA256Constants::Contents).should == SHA256Constants::Hexdigest
    Digest::SHA2.hexdigest("").should == SHA256Constants::BlankHexdigest
  end

end
