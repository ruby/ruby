#
# utils.rb -- Miscellaneous utilities
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: utils.rb,v 1.10 2003/02/16 22:22:54 gotoyuzo Exp $

require 'socket'
require 'fcntl'
begin
  require 'etc'
rescue LoadError
  nil
end

module WEBrick
  module Utils
    def set_non_blocking(io)
      flag = File::NONBLOCK
      if defined?(Fcntl::F_GETFL)
        flag |= io.fcntl(Fcntl::F_GETFL)
      end
      io.fcntl(Fcntl::F_SETFL, flag)
    end
    module_function :set_non_blocking

    def set_close_on_exec(io)
      if defined?(Fcntl::FD_CLOEXEC)
        io.fcntl(Fcntl::FD_CLOEXEC, 1)
      end
    end
    module_function :set_close_on_exec

    def su(user)
      if defined?(Etc)
        pw = Etc.getpwnam(user)
        Process::initgroups(user, pw.gid)
        Process::Sys::setgid(pw.gid)
        Process::Sys::setuid(pw.uid)
      else
        warn("WEBrick::Utils::su doesn't work on this platform")
      end
    end
    module_function :su

    def getservername
      host = Socket::gethostname
      begin
        Socket::gethostbyname(host)[0]
      rescue
        host
      end
    end
    module_function :getservername

    def create_listeners(address, port, logger=nil)
      unless port
        raise ArgumentError, "must specify port"
      end
      res = Socket::getaddrinfo(address, port,
                                Socket::AF_UNSPEC,   # address family
                                Socket::SOCK_STREAM, # socket type
                                0,                   # protocol
                                Socket::AI_PASSIVE)  # flag
      last_error = nil
      sockets = []
      res.each{|ai|
        begin
          logger.debug("TCPServer.new(#{ai[3]}, #{port})") if logger
          sock = TCPServer.new(ai[3], port)
          port = sock.addr[1] if port == 0
          Utils::set_close_on_exec(sock)
          sockets << sock
        rescue => ex
          logger.warn("TCPServer Error: #{ex}") if logger
          last_error  = ex
        end
      }
      raise last_error if sockets.empty?
      return sockets
    end
    module_function :create_listeners

    RAND_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                 "0123456789" +
                 "abcdefghijklmnopqrstuvwxyz" 

    def random_string(len)
      rand_max = RAND_CHARS.size
      ret = "" 
      len.times{ ret << RAND_CHARS[rand(rand_max)] }
      ret 
    end
    module_function :random_string

  end
end
