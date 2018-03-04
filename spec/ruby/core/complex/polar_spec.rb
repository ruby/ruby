require_relative '../../shared/complex/polar'

describe "Complex.polar" do
  it_behaves_like :complex_polar_class, :polar

  it "raises a TypeError when given non real arguments" do
    lambda{ Complex.polar(nil)      }.should raise_error(TypeError)
    lambda{ Complex.polar(nil, nil) }.should raise_error(TypeError)
  end
end

describe "Complex#polar" do
  it_behaves_like :complex_polar, :polar
end
