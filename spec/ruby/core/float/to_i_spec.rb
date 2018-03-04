require_relative '../../spec_helper'
require_relative 'shared/to_i'

describe "Float#to_i" do
  it_behaves_like :float_to_i, :to_i
end
