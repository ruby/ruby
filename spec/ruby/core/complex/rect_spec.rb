require_relative '../../shared/complex/rect'

describe "Complex#rect" do
  it_behaves_like :complex_rect, :rect
end

describe "Complex.rect" do
  it_behaves_like :complex_rect_class, :rect
end
