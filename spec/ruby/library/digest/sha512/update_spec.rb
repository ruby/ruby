require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/update'

describe "Digest::SHA512#update" do
  it_behaves_like :sha512_update, :update
end
