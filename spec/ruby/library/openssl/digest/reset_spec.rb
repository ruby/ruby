require_relative '../../../spec_helper'
require_relative '../../../library/digest/sha1/shared/constants'
require_relative '../../../library/digest/sha256/shared/constants'
require_relative '../../../library/digest/sha384/shared/constants'
require_relative '../../../library/digest/sha512/shared/constants'
require 'openssl'

describe "OpenSSL::Digest#reset" do
  it "works for a SHA1 digest" do
    digest = OpenSSL::Digest.new('sha1', SHA1Constants::Contents)
    digest.reset
    digest.update(SHA1Constants::Contents)
    digest.digest.should == SHA1Constants::Digest
  end

  it "works for a SHA256 digest" do
    digest = OpenSSL::Digest.new('sha256', SHA256Constants::Contents)
    digest.reset
    digest.update(SHA256Constants::Contents)
    digest.digest.should == SHA256Constants::Digest
  end

  it "works for a SHA384 digest" do
    digest = OpenSSL::Digest.new('sha384', SHA384Constants::Contents)
    digest.reset
    digest.update(SHA384Constants::Contents)
    digest.digest.should == SHA384Constants::Digest
  end

  it "works for a SHA512 digest" do
    digest = OpenSSL::Digest.new('sha512', SHA512Constants::Contents)
    digest.reset
    digest.update(SHA512Constants::Contents)
    digest.digest.should == SHA512Constants::Digest
  end
end
