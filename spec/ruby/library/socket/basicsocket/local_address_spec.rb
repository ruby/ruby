require_relative '../spec_helper'
require_relative '../shared/address'

describe 'BasicSocket#local_address' do
  it_behaves_like :socket_local_remote_address, :local_address, -> socket {
    a2 = BasicSocket.for_fd(socket.fileno)
    a2.autoclose = false
    a2.local_address
  }
end
