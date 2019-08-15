require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/update'

describe "Digest::SHA256#update" do
  it_behaves_like :sha256_update, :update
end
