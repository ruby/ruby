require_relative '../../spec_helper'
require_relative 'shared/rect'

describe "Complex#rectangular" do
  it_behaves_like :complex_rect, :rectangular
end

describe "Complex.rectangular" do
  it_behaves_like :complex_rect_class, :rectangular
end
