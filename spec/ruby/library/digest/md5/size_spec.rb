require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/length'

describe "Digest::MD5#size" do
  it_behaves_like :md5_length, :size
end
