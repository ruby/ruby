require_relative '../../shared/complex/inspect'

describe "Complex#inspect" do
  it_behaves_like :complex_inspect, :inspect
end
