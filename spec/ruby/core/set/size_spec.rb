require_relative '../../spec_helper'
require_relative 'shared/length'

describe "Set#size" do
  it_behaves_like :set_length, :size
end
