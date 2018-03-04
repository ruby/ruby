require_relative '../../../spec_helper'
require_relative 'shared/random_bytes'

if defined?(OpenSSL::Random.pseudo_bytes)
  describe "OpenSSL::Random.pseudo_bytes" do
    it_behaves_like :openssl_random_bytes, :pseudo_bytes
  end
end
