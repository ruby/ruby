require_relative '../../spec_helper'
require_relative 'shared/rect'

describe "Numeric#rectangular" do
  it_behaves_like :numeric_rect, :rectangular
end
