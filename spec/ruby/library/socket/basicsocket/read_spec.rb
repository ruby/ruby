require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#read" do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before :each do
      @r = Socket.new(family, :DGRAM)
      @w = Socket.new(family, :DGRAM)

      @r.bind(Socket.pack_sockaddr_in(0, ip_address))
      @w.send("aaa", 0, @r.getsockname)
    end

    after :each do
      @r.close unless @r.closed?
      @w.close unless @w.closed?
    end

    it "receives data after it's ready" do
      @r.read(3).should == "aaa"
    end

    it 'returned data is binary encoded regardless of the external encoding' do
      @r.read(3).encoding.should == Encoding::BINARY

      @w.send("bbb", 0, @r.getsockname)
      @r.set_encoding(Encoding::UTF_8)
      buffer = @r.read(3)
      buffer.should == "bbb"
      buffer.encoding.should == Encoding::BINARY
    end

    it 'replaces the content of the provided buffer without changing its encoding' do
      buffer = "initial data".dup.force_encoding(Encoding::UTF_8)

      @r.read(3, buffer)
      buffer.should == "aaa"
      buffer.encoding.should == Encoding::UTF_8

      @w.send("bbb", 0, @r.getsockname)
      @r.set_encoding(Encoding::ISO_8859_1)
      @r.read(3, buffer)
      buffer.should == "bbb"
      buffer.encoding.should == Encoding::UTF_8
    end
  end
end
