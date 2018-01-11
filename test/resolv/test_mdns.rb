# frozen_string_literal: false
require 'test/unit'
require 'resolv'

class TestResolvMDNS < Test::Unit::TestCase
  def test_mdns_each_address
    mdns = Resolv::MDNS.new
    def mdns.each_resource(name, typeclass)
      if typeclass == Resolv::DNS::Resource::IN::A
        yield typeclass.new("127.0.0.1")
      else
        yield typeclass.new("::1")
      end
    end
    [
      ["example.com", []],
      ["foo.local", ["127.0.0.1"]],
    ].each do |name, expect|
      results = []
      mdns.each_address(name) do |result|
        results << result.to_s
      end
      assert_equal expect, results, "GH-1484"
    end
  end
end
