require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/length'

describe "Digest::MD5#length" do
  it_behaves_like :md5_length, :length
end
