require 'socket'
require 'resolv'

class BasicSocket
  alias original_resolv_send send
  def send(mesg, flags, *rest)
    rest[0] = Resolv.getaddress(rest[0]).to_s unless rest.empty?
    original_resolv_send(mesg, flags, *rest)
  end
end

class << IPSocket
  alias original_resolv_getaddress getaddress
  def getaddress(host)
    return Resolv.getaddress(host).to_s
  end
end

class TCPSocket
  alias original_resolv_initialize initialize
  def initialize(host, serv, *rest)
    rest[0] = Resolv.getaddress(rest[0]).to_s unless rest.empty?
    original_resolv_initialize(Resolv.getaddress(host).to_s, serv, *rest)
  end
end

class UDPSocket
  alias original_resolv_bind bind
  def bind(host, port)
    original_resolv_bind(Resolv.getaddress(host).to_s, port)
  end

  alias original_resolv_connect connect
  def connect(host, port)
    original_resolv_connect(Resolv.getaddress(host).to_s, port)
  end

  alias original_resolv_send send
  def send(mesg, flags, *rest)
    rest[0] = Resolv.getaddress(rest[0]).to_s unless rest.empty?
    original_resolv_send(mesg, flags, *rest)
  end
end

class SOCKSSocket
  alias original_resolv_initialize initialize
  def initialize(host, serv)
    original_resolv_initialize(Resolv.getaddress(host).to_s, port)
  end
end if defined? SOCKSSocket
