require_relative '../../../spec_helper'
require_relative 'shared/random_bytes'

describe "OpenSSL::Random.random_bytes" do
  it_behaves_like :openssl_random_bytes, :random_bytes
end
