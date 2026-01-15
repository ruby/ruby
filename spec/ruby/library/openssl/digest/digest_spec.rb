require_relative '../../../spec_helper'
require_relative '../../../library/digest/sha1/shared/constants'
require_relative '../../../library/digest/sha256/shared/constants'
require_relative '../../../library/digest/sha384/shared/constants'
require_relative '../../../library/digest/sha512/shared/constants'
require 'openssl'

describe "OpenSSL::Digest class methods" do
  describe ".digest" do
    it "returns a SHA1 digest" do
      OpenSSL::Digest.digest('sha1', SHA1Constants::Contents).should == SHA1Constants::Digest
    end

    it "returns a SHA256 digest" do
      OpenSSL::Digest.digest('sha256', SHA256Constants::Contents).should == SHA256Constants::Digest
    end

    it "returns a SHA384 digest" do
      OpenSSL::Digest.digest('sha384', SHA384Constants::Contents).should == SHA384Constants::Digest
    end

    it "returns a SHA512 digest" do
      OpenSSL::Digest.digest('sha512', SHA512Constants::Contents).should == SHA512Constants::Digest
    end
  end

  describe ".hexdigest" do
    it "returns a SHA1 hexdigest" do
      OpenSSL::Digest.hexdigest('sha1', SHA1Constants::Contents).should == SHA1Constants::Hexdigest
    end

    it "returns a SHA256 hexdigest" do
      OpenSSL::Digest.hexdigest('sha256', SHA256Constants::Contents).should == SHA256Constants::Hexdigest
    end

    it "returns a SHA384 hexdigest" do
      OpenSSL::Digest.hexdigest('sha384', SHA384Constants::Contents).should == SHA384Constants::Hexdigest
    end

    it "returns a SHA512 hexdigest" do
      OpenSSL::Digest.hexdigest('sha512', SHA512Constants::Contents).should == SHA512Constants::Hexdigest
    end
  end

  describe ".base64digest" do
    it "returns a SHA1 base64digest" do
      OpenSSL::Digest.base64digest('sha1', SHA1Constants::Contents).should == SHA1Constants::Base64digest
    end

    it "returns a SHA256 base64digest" do
      OpenSSL::Digest.base64digest('sha256', SHA256Constants::Contents).should == SHA256Constants::Base64digest
    end

    it "returns a SHA384 base64digest" do
      OpenSSL::Digest.base64digest('sha384', SHA384Constants::Contents).should == SHA384Constants::Base64digest
    end

    it "returns a SHA512 base64digest" do
      OpenSSL::Digest.base64digest('sha512', SHA512Constants::Contents).should == SHA512Constants::Base64digest
    end
  end
end
