require_relative '../../../spec_helper'
require 'openssl'

describe "OpenSSL::KDF.pbkdf2_hmac" do
  before :each do
    @defaults = {
      salt: "\x00".b * 16,
      iterations: 20_000,
      length: 16,
      hash: "sha1"
    }
  end

  it "creates the same value with the same input" do
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "supports nullbytes embedded in the password" do
    key = OpenSSL::KDF.pbkdf2_hmac("sec\x00ret".b, **@defaults)
    key.should == "\xB9\x7F\xB0\xC2\th\xC8<\x86\xF3\x94Ij7\xEF\xF1".b
  end

  it "coerces the password into a String using #to_str" do
    pass = mock("pass")
    pass.should_receive(:to_str).and_return("secret")
    key = OpenSSL::KDF.pbkdf2_hmac(pass, **@defaults)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "coerces the salt into a String using #to_str" do
    salt = mock("salt")
    salt.should_receive(:to_str).and_return("\x00".b * 16)
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, salt: salt)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "coerces the iterations into an Integer using #to_int" do
    iterations = mock("iterations")
    iterations.should_receive(:to_int).and_return(20_000)
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, iterations: iterations)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "coerces the length into an Integer using #to_int" do
    length = mock("length")
    length.should_receive(:to_int).and_return(16)
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, length: length)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "accepts a OpenSSL::Digest object as hash" do
    hash = OpenSSL::Digest.new("sha1")
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, hash: hash)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0".b
  end

  it "accepts an empty password" do
    key = OpenSSL::KDF.pbkdf2_hmac("", **@defaults)
    key.should == "k\x9F-\xB1\xF7\x9A\v\xA1(C\xF9\x85!P\xEF\x8C".b
  end

  it "accepts an empty salt" do
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, salt: "")
    key.should == "\xD5f\xE5\xEA\xF91\x1D\xD3evD\xED\xDB\xE80\x80".b
  end

  it "accepts an empty length" do
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, length: 0)
    key.should.empty?
  end

  it "accepts an arbitrary length" do
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, length: 19)
    key.should == "!\x99+\xF0^\xD0\x8BM\x158\xC4\xAC\x9C\xF1\xF0\xE0\xCF\xBB\x7F".b
  end

  it "accepts any hash function known to OpenSSL" do
    key = OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, hash: "sha512")
    key.should == "N\x12}D\xCE\x99\xDBC\x8E\xEC\xAAr\xEA1\xDF\xFF".b
  end

  it "raises a TypeError when password is not a String and does not respond to #to_str" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac(Object.new, **@defaults)
    }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  it "raises a TypeError when salt is not a String and does not respond to #to_str" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, salt: Object.new)
    }.should raise_error(TypeError, "no implicit conversion of Object into String")
  end

  it "raises a TypeError when iterations is not an Integer and does not respond to #to_int" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, iterations: Object.new)
    }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
  end

  it "raises a TypeError when length is not an Integer and does not respond to #to_int" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, length: Object.new)
    }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
  end

  it "raises a TypeError when hash is neither a String nor an OpenSSL::Digest" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, hash: Object.new)
    }.should raise_error(TypeError, "wrong argument type Object (expected OpenSSL/Digest)")
  end

  it "raises a TypeError when hash is neither a String nor an OpenSSL::Digest, it does not try to call #to_str" do
    hash = mock("hash")
    hash.should_not_receive(:to_str)
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, hash: hash)
    }.should raise_error(TypeError, "wrong argument type MockObject (expected OpenSSL/Digest)")
  end

  it "raises a RuntimeError for unknown digest algorithms" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, hash: "wd40")
    }.should raise_error(RuntimeError, /Unsupported digest algorithm \(wd40\)/)
  end

  it "treats salt as a required keyword" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults.except(:salt))
    }.should raise_error(ArgumentError, 'missing keyword: :salt')
  end

  it "treats iterations as a required keyword" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults.except(:iterations))
    }.should raise_error(ArgumentError, 'missing keyword: :iterations')
  end

  it "treats length as a required keyword" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults.except(:length))
    }.should raise_error(ArgumentError, 'missing keyword: :length')
  end

  it "treats hash as a required keyword" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults.except(:hash))
    }.should raise_error(ArgumentError, 'missing keyword: :hash')
  end

  it "treats all keywords as required" do
    -> {
      OpenSSL::KDF.pbkdf2_hmac("secret")
    }.should raise_error(ArgumentError, 'missing keywords: :salt, :iterations, :length, :hash')
  end

  guard -> { OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30000000 } do
    it "raises an OpenSSL::KDF::KDFError for 0 or less iterations" do
      -> {
        OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, iterations: 0)
      }.should raise_error(OpenSSL::KDF::KDFError, "PKCS5_PBKDF2_HMAC: invalid iteration count")

      -> {
        OpenSSL::KDF.pbkdf2_hmac("secret", **@defaults, iterations: -1)
      }.should raise_error(OpenSSL::KDF::KDFError, /PKCS5_PBKDF2_HMAC/)
    end
  end
end
