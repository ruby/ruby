require_relative "../../../spec_helper"
require_relative 'shared/new'

describe "TCPSocket.open" do
  it_behaves_like :tcpsocket_new, :open
end
