require 'soap/rpc/driver'

ExchangeServiceNamespace = 'http://tempuri.org/exchangeService'

class Exchange
  ForeignServer = "http://services.xmethods.net/soap"
  Namespace = "urn:xmethods-CurrencyExchange"

  def initialize
    @drv = SOAP::RPC::Driver.new(ForeignServer, Namespace)
    @drv.add_method("getRate", "country1", "country2")
  end

  def rate(country1, country2)
    return @drv.getRate(country1, country2)
  end
end
