require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#data' do
    it 'returns the data as a String' do
      Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, 'ugh').data.should == 'ugh'
    end
  end
end
