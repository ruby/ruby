require_relative '../../../../library/digest/sha1/shared/constants'
require_relative '../../../../library/digest/sha256/shared/constants'
require_relative '../../../../library/digest/sha384/shared/constants'
require_relative '../../../../library/digest/sha512/shared/constants'
require 'openssl'

describe :openssl_digest_update, shared: true do
  context "when given input as a single string" do
    it "returns a SHA1 digest" do
      digest = OpenSSL::Digest.new('sha1')
      digest.send(@method, SHA1Constants::Contents)
      digest.digest.should == SHA1Constants::Digest
    end

    it "returns a SHA256 digest" do
      digest = OpenSSL::Digest.new('sha256')
      digest.send(@method, SHA256Constants::Contents)
      digest.digest.should == SHA256Constants::Digest
    end

    it "returns a SHA384 digest" do
      digest = OpenSSL::Digest.new('sha384')
      digest.send(@method, SHA384Constants::Contents)
      digest.digest.should == SHA384Constants::Digest
    end

    it "returns a SHA512 digest" do
      digest = OpenSSL::Digest.new('sha512')
      digest.send(@method, SHA512Constants::Contents)
      digest.digest.should == SHA512Constants::Digest
    end
  end

  context "when given input as multiple smaller substrings" do
    it "returns a SHA1 digest" do
      digest = OpenSSL::Digest.new('sha1')
      SHA1Constants::Contents.each_char { |b| digest.send(@method, b) }
      digest.digest.should == SHA1Constants::Digest
    end

    it "returns a SHA256 digest" do
      digest = OpenSSL::Digest.new('sha256')
      SHA256Constants::Contents.each_char { |b| digest.send(@method, b) }
      digest.digest.should == SHA256Constants::Digest
    end

    it "returns a SHA384 digest" do
      digest = OpenSSL::Digest.new('sha384')
      SHA384Constants::Contents.each_char { |b| digest.send(@method, b) }
      digest.digest.should == SHA384Constants::Digest
    end

    it "returns a SHA512 digest" do
      digest = OpenSSL::Digest.new('sha512')
      SHA512Constants::Contents.each_char { |b| digest.send(@method, b) }
      digest.digest.should == SHA512Constants::Digest
    end
  end

  context "when input is not a String and responds to #to_str" do
    it "returns a SHA1 digest" do
      str = mock('str')
      str.should_receive(:to_str).and_return(SHA1Constants::Contents)
      digest = OpenSSL::Digest.new('sha1')
      digest.send(@method, str)
      digest.digest.should == SHA1Constants::Digest
    end

    it "returns a SHA256 digest" do
      str = mock('str')
      str.should_receive(:to_str).and_return(SHA256Constants::Contents)
      digest = OpenSSL::Digest.new('sha256')
      digest.send(@method, str)
      digest.digest.should == SHA256Constants::Digest
    end

    it "returns a SHA384 digest" do
      str = mock('str')
      str.should_receive(:to_str).and_return(SHA384Constants::Contents)
      digest = OpenSSL::Digest.new('sha384')
      digest.send(@method, str)
      digest.digest.should == SHA384Constants::Digest
    end

    it "returns a SHA512 digest" do
      str = mock('str')
      str.should_receive(:to_str).and_return(SHA512Constants::Contents)
      digest = OpenSSL::Digest.new('sha512')
      digest.send(@method, str)
      digest.digest.should == SHA512Constants::Digest
    end
  end

  context "when input is not a String and does not respond to #to_str" do
    it "raises a TypeError with SHA1" do
      digest = OpenSSL::Digest.new('sha1')
      -> {
        digest.send(@method, Object.new)
      }.should raise_error(TypeError, 'no implicit conversion of Object into String')
    end

    it "raises a TypeError with SHA256" do
      digest = OpenSSL::Digest.new('sha256')
      -> {
        digest.send(@method, Object.new)
      }.should raise_error(TypeError, 'no implicit conversion of Object into String')
    end

    it "raises a TypeError with SHA384" do
      digest = OpenSSL::Digest.new('sha384')
      -> {
        digest.send(@method, Object.new)
      }.should raise_error(TypeError, 'no implicit conversion of Object into String')
    end

    it "raises a TypeError with SHA512" do
      digest = OpenSSL::Digest.new('sha512')
      -> {
        digest.send(@method, Object.new)
      }.should raise_error(TypeError, 'no implicit conversion of Object into String')
    end
  end
end
