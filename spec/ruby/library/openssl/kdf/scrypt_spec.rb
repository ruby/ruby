require_relative '../../../spec_helper'
require 'openssl'

# LibreSSL seems not to support scrypt
guard -> { OpenSSL::OPENSSL_VERSION.start_with?('OpenSSL') and OpenSSL::OPENSSL_VERSION_NUMBER >= 0x10100000 } do
  describe "OpenSSL::KDF.scrypt" do
    before :each do
      @defaults = {
        salt: "\x00".b * 16,
        N: 2**14,
        r: 8,
        p: 1,
        length: 32
      }
    end

    it "creates the same value with the same input" do
      key = OpenSSL::KDF.scrypt("secret", **@defaults)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "supports nullbytes embedded into the password" do
      key = OpenSSL::KDF.scrypt("sec\x00ret".b, **@defaults)
      key.should == "\xF9\xA4\xA0\xF1p\xF4\xF0\xCAT\xB4v\xEB\r7\x88N\xF7\x15]Ns\xFCwt4a\xC9\xC6\xA7\x13\x81&".b
    end

    it "coerces the password into a String using #to_str" do
      pass = mock("pass")
      pass.should_receive(:to_str).and_return("secret")
      key = OpenSSL::KDF.scrypt(pass, **@defaults)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "coerces the salt into a String using #to_str" do
      salt = mock("salt")
      salt.should_receive(:to_str).and_return("\x00".b * 16)
      key = OpenSSL::KDF.scrypt("secret", **@defaults, salt: salt)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "coerces the N into an Integer using #to_int" do
      n = mock("N")
      n.should_receive(:to_int).and_return(2**14)
      key = OpenSSL::KDF.scrypt("secret", **@defaults, N: n)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "coerces the r into an Integer using #to_int" do
      r = mock("r")
      r.should_receive(:to_int).and_return(8)
      key = OpenSSL::KDF.scrypt("secret", **@defaults, r: r)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "coerces the p into an Integer using #to_int" do
      p = mock("p")
      p.should_receive(:to_int).and_return(1)
      key = OpenSSL::KDF.scrypt("secret", **@defaults, p: p)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "coerces the length into an Integer using #to_int" do
      length = mock("length")
      length.should_receive(:to_int).and_return(32)
      key = OpenSSL::KDF.scrypt("secret", **@defaults, length: length)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D\x17}\xF2\x84T\xD4)\xC2>\xFE\x93\xE3\xF4".b
    end

    it "accepts an empty password" do
      key = OpenSSL::KDF.scrypt("", **@defaults)
      key.should == "\xAA\xFC\xF5^E\x94v\xFFk\xE6\xF0vR\xE7\x13\xA7\xF5\x15'\x9A\xE4C\x9Dn\x18F_E\xD2\v\e\xB3".b
    end

    it "accepts an empty salt" do
      key = OpenSSL::KDF.scrypt("secret", **@defaults, salt: "")
      key.should == "\x96\xACDl\xCB3/aN\xB0F\x8A#\xD7\x92\xD2O\x1E\v\xBB\xCE\xC0\xAA\xB9\x0F]\xB09\xEA8\xDD\e".b
    end

    it "accepts a zero length" do
      key = OpenSSL::KDF.scrypt("secret", **@defaults, length: 0)
      key.should.empty?
    end

    it "accepts an arbitrary length" do
      key = OpenSSL::KDF.scrypt("secret", **@defaults, length: 19)
      key.should == "h\xB2k\xDF]\xDA\xE1.-(\xCF\xAC\x91D\x8F\xC2a\x9C\x9D".b
    end

    it "raises a TypeError when password is not a String and does not respond to #to_str" do
      -> {
        OpenSSL::KDF.scrypt(Object.new, **@defaults)
      }.should raise_error(TypeError, "no implicit conversion of Object into String")
    end

    it "raises a TypeError when salt is not a String and does not respond to #to_str" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, salt: Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into String")
    end

    it "raises a TypeError when N is not an Integer and does not respond to #to_int" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, N: Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
    end

    it "raises a TypeError when r is not an Integer and does not respond to #to_int" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, r: Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
    end

    it "raises a TypeError when p is not an Integer and does not respond to #to_int" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, p: Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
    end

    it "raises a TypeError when length is not an Integer and does not respond to #to_int" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, length: Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
    end

    it "treats salt as a required keyword" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults.except(:salt))
      }.should raise_error(ArgumentError, 'missing keyword: :salt')
    end

    it "treats N as a required keyword" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults.except(:N))
      }.should raise_error(ArgumentError, 'missing keyword: :N')
    end

    it "treats r as a required keyword" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults.except(:r))
      }.should raise_error(ArgumentError, 'missing keyword: :r')
    end

    it "treats p as a required keyword" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults.except(:p))
      }.should raise_error(ArgumentError, 'missing keyword: :p')
    end

    it "treats length as a required keyword" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults.except(:length))
      }.should raise_error(ArgumentError, 'missing keyword: :length')
    end

    it "treats all keywords as required" do
      -> {
        OpenSSL::KDF.scrypt("secret")
      }.should raise_error(ArgumentError, 'missing keywords: :salt, :N, :r, :p, :length')
    end

    it "requires N to be a power of 2" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, N: 2**14 - 1)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)
    end

    it "requires N to be at least 2" do
      key = OpenSSL::KDF.scrypt("secret", **@defaults, N: 2)
      key.should == "\x06A$a\xA9!\xBE\x01\x85\xA7\x18\xBCEa\x82\xC5\xFEl\x93\xAB\xBD\xF7\x8B\x84\v\xFC\eN\xEBQ\xE6\xD2".b

      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, N: 1)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)

      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, N: 0)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)

      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, N: -1)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)
    end

    it "requires r to be positive" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, r: 0)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)

      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, r: -1)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)
    end

    it "requires p to be positive" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, p: 0)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)

      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, p: -1)
      }.should raise_error(OpenSSL::KDF::KDFError, /EVP_PBE_scrypt/)
    end

    it "requires length to be not negative" do
      -> {
        OpenSSL::KDF.scrypt("secret", **@defaults, length: -1)
      }.should raise_error(ArgumentError, "negative string size (or size too big)")
    end
  end
end
