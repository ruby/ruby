require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)
require File.expand_path('../../shared/pack_sockaddr', __FILE__)

describe "Socket#sockaddr_in" do
  it_behaves_like :socket_pack_sockaddr_in, :sockaddr_in
end
