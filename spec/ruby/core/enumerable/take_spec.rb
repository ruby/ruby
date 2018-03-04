require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/take'

describe "Enumerable#take" do
  it "requires an argument" do
    lambda{ EnumerableSpecs::Numerous.new.take}.should raise_error(ArgumentError)
  end

  describe "when passed an argument" do
    it_behaves_like :enumerable_take, :take
  end
end
