require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "BasicSocket#read_nonblock" do
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
      IO.select([@r], nil, nil, 2)
      @r.read_nonblock(5).should == "aaa"
    end

    platform_is_not :windows do
      it 'returned data is binary encoded regardless of the external encoding' do
        IO.select([@r], nil, nil, 2)
        @r.read_nonblock(1).encoding.should == Encoding::BINARY

        @w.send("bbb", 0, @r.getsockname)
        @r.set_encoding(Encoding::ISO_8859_1)
        IO.select([@r], nil, nil, 2)
        buffer = @r.read_nonblock(3)
        buffer.should == "bbb"
        buffer.encoding.should == Encoding::BINARY
      end
    end

    it 'replaces the content of the provided buffer without changing its encoding' do
      buffer = "initial data".dup.force_encoding(Encoding::UTF_8)

      IO.select([@r], nil, nil, 2)
      @r.read_nonblock(3, buffer)
      buffer.should == "aaa"
      buffer.encoding.should == Encoding::UTF_8

      @w.send("bbb", 0, @r.getsockname)
      @r.set_encoding(Encoding::ISO_8859_1)
      IO.select([@r], nil, nil, 2)
      @r.read_nonblock(3, buffer)
      buffer.should == "bbb"
      buffer.encoding.should == Encoding::UTF_8
    end

    platform_is :linux do
      it 'does not set the IO in nonblock mode' do
        require 'io/nonblock'
        @r.nonblock = false
        IO.select([@r], nil, nil, 2)
        @r.read_nonblock(3).should == "aaa"
        @r.should_not.nonblock?
      end
    end

    platform_is_not :linux, :windows do
      it 'sets the IO in nonblock mode' do
        require 'io/nonblock'
        @r.nonblock = false
        IO.select([@r], nil, nil, 2)
        @r.read_nonblock(3).should == "aaa"
        @r.should.nonblock?
      end
    end
  end
end
