require_relative '../../spec_helper'
require_relative 'shared/to_i'
require_relative 'shared/integer_rounding'
require_relative 'shared/integer_floor_precision'

describe "Integer#floor" do
  it_behaves_like :integer_to_i, :floor
  it_behaves_like :integer_rounding_positive_precision, :floor

  context "with precision" do
    it_behaves_like :integer_floor_precision, :Integer
  end
end
