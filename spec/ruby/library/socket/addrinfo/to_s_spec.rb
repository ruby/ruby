require_relative '../spec_helper'
require_relative 'shared/to_sockaddr'

describe "Addrinfo#to_s" do
  it_behaves_like :socket_addrinfo_to_sockaddr, :to_s
end
