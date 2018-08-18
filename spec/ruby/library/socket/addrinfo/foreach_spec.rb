require_relative '../spec_helper'

describe 'Addrinfo.foreach' do
  it 'yields Addrinfo instances to the supplied block' do
    Addrinfo.foreach('localhost', 80) do |addr|
      addr.should be_an_instance_of(Addrinfo)
    end
  end
end
