require_relative '../../../spec_helper'
require_relative '../../../library/digest/sha1/shared/constants'
require_relative '../../../library/digest/sha256/shared/constants'
require_relative '../../../library/digest/sha384/shared/constants'
require_relative '../../../library/digest/sha512/shared/constants'
require 'openssl'

describe "OpenSSL::Digest#block_length" do
  context "when the digest object is created via a name argument" do
    it "returns a SHA1 block length" do
      OpenSSL::Digest.new('sha1').block_length.should == SHA1Constants::BlockLength
    end

    it "returns a SHA256 block length" do
      OpenSSL::Digest.new('sha256').block_length.should == SHA256Constants::BlockLength
    end

    it "returns a SHA384 block length" do
      OpenSSL::Digest.new('sha384').block_length.should == SHA384Constants::BlockLength
    end

    it "returns a SHA512 block length" do
      OpenSSL::Digest.new('sha512').block_length.should == SHA512Constants::BlockLength
    end
  end

  context "when the digest object is created via a subclass" do
    it "returns a SHA1 block length" do
      OpenSSL::Digest::SHA1.new.block_length.should == SHA1Constants::BlockLength
    end

    it "returns a SHA256 block length" do
      OpenSSL::Digest::SHA256.new.block_length.should == SHA256Constants::BlockLength
    end

    it "returns a SHA384 block length" do
      OpenSSL::Digest::SHA384.new.block_length.should == SHA384Constants::BlockLength
    end

    it "returns a SHA512 block length" do
      OpenSSL::Digest::SHA512.new.block_length.should == SHA512Constants::BlockLength
    end
  end
end
