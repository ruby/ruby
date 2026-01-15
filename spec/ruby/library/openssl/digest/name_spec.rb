require_relative '../../../spec_helper'
require 'openssl'

describe "OpenSSL::Digest#name" do
  it "returns the name of digest" do
    OpenSSL::Digest.new('SHA1').name.should == 'SHA1'
  end

  it "converts the name to the internal representation of OpenSSL" do
    OpenSSL::Digest.new('sha1').name.should == 'SHA1'
  end

  it "works on subclasses too" do
    OpenSSL::Digest::SHA1.new.name.should == 'SHA1'
  end
end
