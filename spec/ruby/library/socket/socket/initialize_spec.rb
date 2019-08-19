require_relative '../spec_helper'

describe 'Socket#initialize' do
  before do
    @socket = nil
  end

  after do
    @socket.close if @socket
  end

  describe 'using an Integer as the 1st and 2nd arguments' do
    it 'returns a Socket' do
      @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)

      @socket.should be_an_instance_of(Socket)
    end
  end

  describe 'using Symbols as the 1st and 2nd arguments' do
    it 'returns a Socket' do
      @socket = Socket.new(:INET, :STREAM)

      @socket.should be_an_instance_of(Socket)
    end
  end

  describe 'using Strings as the 1st and 2nd arguments' do
    it 'returns a Socket' do
      @socket = Socket.new('INET', 'STREAM')

      @socket.should be_an_instance_of(Socket)
    end
  end

  describe 'using objects that respond to #to_str' do
    it 'returns a Socket' do
      family = mock(:family)
      type   = mock(:type)

      family.stub!(:to_str).and_return('AF_INET')
      type.stub!(:to_str).and_return('STREAM')

      @socket = Socket.new(family, type)

      @socket.should be_an_instance_of(Socket)
    end

    it 'raises TypeError when the #to_str method does not return a String' do
      family = mock(:family)
      type   = mock(:type)

      family.stub!(:to_str).and_return(Socket::AF_INET)
      type.stub!(:to_str).and_return(Socket::SOCK_STREAM)

      -> { Socket.new(family, type) }.should raise_error(TypeError)
    end
  end

  describe 'using a custom protocol' do
    it 'returns a Socket when using an Integer' do
      @socket = Socket.new(:INET, :STREAM, Socket::IPPROTO_TCP)

      @socket.should be_an_instance_of(Socket)
    end

    it 'raises TypeError when using a Symbol' do
      -> { Socket.new(:INET, :STREAM, :TCP) }.should raise_error(TypeError)
    end
  end

  it 'sets the do_not_reverse_lookup option' do
    @socket = Socket.new(:INET, :STREAM)

    @socket.do_not_reverse_lookup.should == Socket.do_not_reverse_lookup
  end

  it "sets basic IO accessors" do
    @socket = Socket.new(:INET, :STREAM)
    @socket.lineno.should == 0
  end

  it "sets the socket to binary mode" do
    @socket = Socket.new(:INET, :STREAM)
    @socket.binmode?.should be_true
  end
end
