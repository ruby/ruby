require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/length'

describe "Digest::SHA384#size" do
  it_behaves_like :sha384_length, :size
end
