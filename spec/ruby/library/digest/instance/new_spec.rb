require_relative '../../../spec_helper'
require 'digest'
require_relative '../md5/shared/constants'

describe "Digest::Instance#new" do
  it "returns a copy of the digest instance" do
    digest = Digest::MD5.new
    copy = digest.new
    copy.should_not.equal?(digest)
  end

  it "calls reset" do
    digest = Digest::MD5.new
    digest << "test"
    digest.hexdigest.should != MD5Constants::BlankHexdigest
    copy = digest.new
    copy.hexdigest.should == MD5Constants::BlankHexdigest
  end
end
