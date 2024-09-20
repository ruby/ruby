require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is '3.1' do
  describe "Enumerable#compact" do
    it 'returns array without nil elements' do
      arr = EnumerableSpecs::Numerous.new(nil, 1, 2, nil, true)
      arr.compact.should == [1, 2, true]
    end
  end
end
