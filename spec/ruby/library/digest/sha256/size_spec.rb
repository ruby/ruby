require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/length'

describe "Digest::SHA256#size" do
  it_behaves_like :sha256_length, :size
end
