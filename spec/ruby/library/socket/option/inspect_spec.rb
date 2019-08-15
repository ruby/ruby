require_relative '../spec_helper'
require_relative '../fixtures/classes'


describe 'Socket::Option#inspect' do
  it 'correctly returns SO_LINGER value' do
    value = Socket::Option.linger(nil, 0).inspect
    value.should == '#<Socket::Option: UNSPEC SOCKET LINGER off 0sec>'

    value = Socket::Option.linger(false, 30).inspect
    value.should == '#<Socket::Option: UNSPEC SOCKET LINGER off 30sec>'

    value = Socket::Option.linger(true, 0).inspect
    value.should == '#<Socket::Option: UNSPEC SOCKET LINGER on 0sec>'

    value = Socket::Option.linger(true, 30).inspect
    value.should == '#<Socket::Option: UNSPEC SOCKET LINGER on 30sec>'
  end
end
