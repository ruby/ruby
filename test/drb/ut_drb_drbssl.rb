# frozen_string_literal: false
require_relative "ut_drb"
require 'drb/ssl'

if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <manager-uri> <name>" unless it
    it
  end

  module DRbTests

    TEST_KEY_DH1024 = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
-----END DH PARAMETERS-----
  _end_of_pem_

  end

  config = Hash.new
  config[:SSLTmpDhCallback] = proc { DRbTests::TEST_KEY_DH1024 }
  config[:SSLVerifyMode] = OpenSSL::SSL::VERIFY_PEER
  config[:SSLVerifyCallback] = lambda{|ok,x509_store|
    true
  }
  config[:SSLCertName] =
    [ ["C","JP"], ["O","Foo.DRuby.Org"], ["CN", "Sample"] ]

  DRb::DRbServer.default_argc_limit(8)
  DRb::DRbServer.default_load_limit(4096)
  DRb.start_service('drbssl://localhost:0', DRbTests::DRbEx.new, config)
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end

