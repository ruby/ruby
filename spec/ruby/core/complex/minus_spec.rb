require_relative '../../shared/complex/minus'

describe "Complex#-" do
  it_behaves_like :complex_minus, :-
end
