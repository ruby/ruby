require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/length'

describe "Digest::SHA384#length" do
  it_behaves_like :sha384_length, :length
end
