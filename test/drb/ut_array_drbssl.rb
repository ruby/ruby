require 'drb/drb'
require 'drb/extserv'
require 'drb/ssl'

if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <uri> <name>" unless it
    it
  end

  TEST_KEY_DH1024 = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAKnKQ8MNK6nYZzLrrcuTsLxuiJGXoOO5gT+tljOTbHBuiktdMTITzIY0
pFxIvjG05D7HoBZQfrR0c92NGWPkAiCkhQKB8JCbPVzwNLDy6DZ0pmofDKrEsYHG
AQjjxMXhwULlmuR/K+WwlaZPiLIBYalLAZQ7ZbOPeVkJ8ePao0eLAgEC
-----END DH PARAMETERS-----
  _end_of_pem_

  TEST_KEY_DH1024.priv_key = OpenSSL::BN.new("48561834C67E65FFD2A9B47F41E5E78FDC95C387428FDB1E4B0188B64D1643C3A8D3455B945B7E8C4D166010C7C2CE23BFB9BEF43D0348FE7FA5284B0225E7FE1537546D114E3D8A4411B9B9351AB451E1A358F50ED61B1F00DA29336EEBBD649980AC86D76AF8BBB065298C2052672EEF3EF13AB47A15275FC2836F3AC74CEA", 16)

  config = Hash.new
  config[:SSLTmpDhCallback] = proc { TEST_KEY_DH1024 }
  config[:SSLVerifyMode] = OpenSSL::SSL::VERIFY_PEER
  config[:SSLVerifyCallback] = lambda{|ok,x509_store|
    true
  }
  config[:SSLCertName] =
    [ ["C","JP"], ["O","Foo.DRuby.Org"], ["CN", "Sample"] ]

  DRb.start_service('drbssl://localhost:0', [1, 2, 'III', 4, "five", 6], config)
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end

