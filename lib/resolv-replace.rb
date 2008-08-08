require 'socket'
require 'resolv'

class << IPSocket
  alias original_resolv_getaddress getaddress
  def getaddress(host)
    begin
      return Resolv.getaddress(host).to_s
    rescue Resolv::ResolvError
      raise SocketError, "Hostname not known: #{host}"
    end
  end
end

class TCPSocket
  alias original_resolv_initialize initialize
  def initialize(host, serv, *rest)
    rest[0] = IPSocket.getaddress(rest[0]) unless rest.empty?
    original_resolv_initialize(IPSocket.getaddress(host), serv, *rest)
  end
end

class UDPSocket
  alias original_resolv_bind bind
  def bind(host, port)
    host = IPSocket.getaddress(host) if host != ""
    original_resolv_bind(host, port)
  end

  alias original_resolv_connect connect
  def connect(host, port)
    original_resolv_connect(IPSocket.getaddress(host), port)
  end

  alias original_resolv_send send
  def send(mesg, flags, *rest)
    if rest.length == 2
      host, port = rest
      begin
        addrs = Resolv.getaddresses(host)
      rescue Resolv::ResolvError
        raise SocketError, "Hostname not known: #{host}"
      end
      err = nil
      addrs[0...-1].each {|addr|
        begin
          return original_resolv_send(mesg, flags, addr, port)
        rescue SystemCallError
        end
      }
      original_resolv_send(mesg, flags, addrs[-1], port)
    else
      original_resolv_send(mesg, flags, *rest)
    end
  end
end

class SOCKSSocket
  alias original_resolv_initialize initialize
  def initialize(host, serv)
    original_resolv_initialize(IPSocket.getaddress(host), port)
  end
end if defined? SOCKSSocket
