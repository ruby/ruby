require_relative '../../spec_helper'
require_relative 'shared/constants'
require 'openssl'

describe "OpenSSL::Cipher's CipherError" do
  it "exists under OpenSSL::Cipher namespace" do
    OpenSSL::Cipher.should have_constant :CipherError
  end
end
