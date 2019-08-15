require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#type' do
    it 'returns the type as an Integer' do
      Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, '').type.should == Socket::SCM_RIGHTS
    end
  end
end
