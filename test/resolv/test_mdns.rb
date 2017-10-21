# frozen_string_literal: false
require 'test/unit'
require 'resolv'

class TestResolvMDNS < Test::Unit::TestCase
  def setup
  end

  def test_mdns_each_address
    begin
      mdns = Resolv::MDNS.new
      mdns.each_resource '_http._tcp.local', Resolv::DNS::Resource::IN::PTR do |r|
        srv = mdns.getresource r.name, Resolv::DNS::Resource::IN::SRV
        mdns.each_address(srv.target) do |result|
          assert_not_nil(result)
        end
      end
    rescue Errno::EADDRNOTAVAIL
      # Handle Raspberry Pi environment.
    end
  end
end
