require 'resolv'

class BasicSocket
  alias original_resolv_send send
  def send(mesg, flags, *rest)
    rest[0] = Resolv.getaddress(rest[0]).to_s if 0 < rest.length
    original_resolv_send(mesg, flags, *rest)
  end
end

class << IPSocket
  alias original_resolv_getaddress getaddress
  def getaddress(host)
    return Resolv.getaddress(host).to_s
  end
end

class << TCPSocket
  alias original_resolv_new new
  def new(host, service)
    original_resolv_new(Resolv.getaddress(host).to_s, service)
  end

  alias original_resolv_open open
  def open(host, service)
    original_resolv_open(Resolv.getaddress(host).to_s, service)
  end
end

class UDPSocket
  alias original_resolv_connect connect
  def connect(host, port)
    original_resolv_connect(Resolv.getaddress(host).to_s, port)
  end

  alias original_resolv_send send
  def send(mesg, flags, *rest)
    rest[0] = Resolv.getaddress(rest[0]).to_s if 0 < rest.length
    original_resolv_send(mesg, flags, *rest)
  end
end
