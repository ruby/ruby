require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/take'
require_relative 'shared/value_packing'

describe "Enumerable#take" do
  it "requires an argument" do
    ->{ EnumerableSpecs::Numerous.new.take}.should.raise(ArgumentError)
  end

  describe "when passed an argument" do
    it_behaves_like :enumerable_take, :take
  end

  describe "value packing of source yields" do
    before :each do
      @take = -> e { e.take(1) }
    end
    it_behaves_like :enumerable_value_packing, nil
  end
end
