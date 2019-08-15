require_relative '../../spec_helper'
require_relative 'shared/rect'

describe "Numeric#rect" do
  it_behaves_like :numeric_rect, :rect
end
