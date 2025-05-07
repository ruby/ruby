require_relative '../../spec_helper'
require_relative 'shared/length'

describe "Set#length" do
  it_behaves_like :set_length, :length
end
