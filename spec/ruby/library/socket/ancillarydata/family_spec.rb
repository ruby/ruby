require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#family' do
    it 'returns the family as an Integer' do
      Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, '').family.should == Socket::AF_INET
    end
  end
end
