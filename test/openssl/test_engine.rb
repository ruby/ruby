require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestEngine < Test::Unit::TestCase

  def test_engines_free # [ruby-dev:44173]
    OpenSSL::Engine.load
    OpenSSL::Engine.engines
    OpenSSL::Engine.engines
  end

end

end
