require_relative '../../../spec_helper'
require_relative 'shared/update'

describe "OpenSSL::Digest#update" do
  it_behaves_like :openssl_digest_update, :update
end
