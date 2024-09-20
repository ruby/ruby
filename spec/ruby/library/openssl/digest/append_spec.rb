require_relative '../../../spec_helper'
require_relative 'shared/update'

describe "OpenSSL::Digest#<<" do
  it_behaves_like :openssl_digest_update, :<<
end
