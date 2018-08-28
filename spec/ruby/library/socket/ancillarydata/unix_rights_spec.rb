require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData.unix_rights' do
    describe 'using a list of IO objects' do
      before do
        @data = Socket::AncillaryData.unix_rights(STDOUT, STDERR)
      end

      it 'sets the family to AF_UNIX' do
        @data.family.should == Socket::AF_UNIX
      end

      it 'sets the level to SOL_SOCKET' do
        @data.level.should == Socket::SOL_SOCKET
      end

      it 'sets the type to SCM_RIGHTS' do
        @data.type.should == Socket::SCM_RIGHTS
      end

      it 'sets the data to a String containing the file descriptors' do
        @data.data.unpack('I*').should == [STDOUT.fileno, STDERR.fileno]
      end
    end

    describe 'using non IO objects' do
      it 'raises TypeError' do
        lambda { Socket::AncillaryData.unix_rights(10) }.should raise_error(TypeError)
      end
    end
  end

  describe 'Socket::AncillaryData#unix_rights' do
    it 'returns the data as an Array of IO objects' do
      data = Socket::AncillaryData.unix_rights(STDOUT, STDERR)

      data.unix_rights.should == [STDOUT, STDERR]
    end

    it 'returns nil when the data is not a list of file descriptors' do
      data = Socket::AncillaryData.new(:UNIX, :SOCKET, :RIGHTS, '')

      data.unix_rights.should be_nil
    end

    it 'raises TypeError when the level is not SOL_SOCKET' do
      data = Socket::AncillaryData.new(:INET, :IP, :RECVTTL, '')

      lambda { data.unix_rights }.should raise_error(TypeError)
    end

    platform_is_not :"solaris2.10", :aix do
      it 'raises TypeError when the type is not SCM_RIGHTS' do
        data = Socket::AncillaryData.new(:INET, :SOCKET, :TIMESTAMP, '')

        lambda { data.unix_rights }.should raise_error(TypeError)
      end
    end
  end
end
