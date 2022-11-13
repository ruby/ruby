require_relative '../../../spec_helper'

ruby_version_is '3.1' do
  describe "Enumerator::Lazy#compact" do
    it 'returns array without nil elements' do
      arr = [1, nil, 3, false, 5].to_enum.lazy.compact
      arr.should be_an_instance_of(Enumerator::Lazy)
      arr.force.should == [1, 3, false, 5]
    end
  end
end
