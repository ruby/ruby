require_relative '../spec_helper'
require_relative '../fixtures/classes'

ruby_version_is "2.5" do
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
        @r.recv_nonblock(5).should == "aaa"
      end

      platform_is :linux do
        it 'does not set the IO in nonblock mode' do
          require 'io/nonblock'
          @r.nonblock?.should == false
          IO.select([@r], nil, nil, 2)
          @r.read_nonblock(3).should == "aaa"
          @r.nonblock?.should == false
        end
      end

      platform_is_not :linux, :windows do
        it 'sets the IO in nonblock mode' do
          require 'io/nonblock'
          @r.nonblock?.should == false
          IO.select([@r], nil, nil, 2)
          @r.read_nonblock(3).should == "aaa"
          @r.nonblock?.should == true
        end
      end
    end
  end
end
