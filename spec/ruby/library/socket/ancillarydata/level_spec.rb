require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#level' do
    it 'returns the level as an Integer' do
      Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, '').level.should == Socket::SOL_SOCKET
    end
  end
end
