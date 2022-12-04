require_relative '../../spec_helper'

platform_is_not :windows do
  describe "IO#nonblock?" do
    before :all do
      require 'io/nonblock'
    end

    it "returns false for a file by default" do
      File.open(__FILE__) do |f|
        f.nonblock?.should == false
      end
    end

    ruby_version_is ""..."3.0" do
      it "returns false for pipe by default" do
        r, w = IO.pipe
        begin
          r.nonblock?.should == false
          w.nonblock?.should == false
        ensure
          r.close
          w.close
        end
      end

      it "returns false for socket by default" do
        require 'socket'
        TCPServer.open(0) do |socket|
          socket.nonblock?.should == false
        end
      end
    end

    ruby_version_is "3.0" do
      it "returns true for pipe by default" do
        r, w = IO.pipe
        begin
          r.nonblock?.should == true
          w.nonblock?.should == true
        ensure
          r.close
          w.close
        end
      end

      it "returns true for socket by default" do
        require 'socket'
        TCPServer.open(0) do |socket|
          socket.nonblock?.should == true
        end
      end
    end
  end

  describe "IO#nonblock=" do
    before :all do
      require 'io/nonblock'
    end

    it "changes the IO to non-blocking mode" do
      File.open(__FILE__) do |f|
        f.nonblock = true
        f.nonblock?.should == true
        f.nonblock = false
        f.nonblock?.should == false
      end
    end
  end
end
