require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData.int' do
    before do
      @data = Socket::AncillaryData.int(:INET, :SOCKET, :RIGHTS, 4)
    end

    it 'returns a Socket::AncillaryData' do
      @data.should be_an_instance_of(Socket::AncillaryData)
    end

    it 'sets the family to AF_INET' do
      @data.family.should == Socket::AF_INET
    end

    it 'sets the level SOL_SOCKET' do
      @data.level.should == Socket::SOL_SOCKET
    end

    it 'sets the type SCM_RIGHTS' do
      @data.type.should == Socket::SCM_RIGHTS
    end

    it 'sets the data to a packed String' do
      @data.data.should == [4].pack('I')
    end
  end

  describe 'Socket::AncillaryData#int' do
    it 'returns the data as an Integer' do
      data = Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, 4)

      data.int.should == 4
    end

    it 'raises when the data is not an Integer' do
      data = Socket::AncillaryData.new(:UNIX, :SOCKET, :RIGHTS, 'ugh')

      -> { data.int }.should raise_error(TypeError)
    end
  end
end
