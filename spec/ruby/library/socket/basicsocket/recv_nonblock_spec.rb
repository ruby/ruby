require_relative '../../../spec_helper'
require_relative '../shared/recv_nonblock'
require_relative '../fixtures/classes'

describe "Socket::BasicSocket#recv_nonblock" do
  it_behaves_like :socket_recv_nonblock, :recv_nonblock
end
