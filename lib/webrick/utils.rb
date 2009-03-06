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
      rand_max = RAND_CHARS.bytesize
      ret = ""
      len.times{ ret << RAND_CHARS[rand(rand_max)] }
      ret
    end
    module_function :random_string

    ###########

    require "thread"
    require "timeout"
    require "singleton"

    class TimeoutHandler
      include Singleton
      TimeoutMutex = Mutex.new

      def TimeoutHandler.register(seconds, exception)
        TimeoutMutex.synchronize{
          instance.register(Thread.current, Time.now + seconds, exception)
        }
      end

      def TimeoutHandler.cancel(id)
        TimeoutMutex.synchronize{
          instance.cancel(Thread.current, id)
        }
      end

      def initialize
        @timeout_info = Hash.new
        Thread.start{
          while true
            now = Time.now
            @timeout_info.each{|thread, ary|
              ary.dup.each{|info|
                time, exception = *info
                interrupt(thread, info.object_id, exception) if time < now
              }
            }
            sleep 0.5
          end
        }
      end

      def interrupt(thread, id, exception)
        TimeoutMutex.synchronize{
          if cancel(thread, id) && thread.alive?
            thread.raise(exception, "execution timeout")
          end
        }
      end

      def register(thread, time, exception)
        @timeout_info[thread] ||= Array.new
        @timeout_info[thread] << [time, exception]
        return @timeout_info[thread].last.object_id
      end

      def cancel(thread, id)
        if ary = @timeout_info[thread]
          ary.delete_if{|info| info.object_id == id }
          if ary.empty?
            @timeout_info.delete(thread)
          end
          return true
        end
        return false
      end
    end

    def timeout(seconds, exception=Timeout::Error)
      return yield if seconds.nil? or seconds.zero?
      # raise ThreadError, "timeout within critical session" if Thread.critical
      id = TimeoutHandler.register(seconds, exception)
      begin
        yield(seconds)
      ensure
        TimeoutHandler.cancel(id)
      end
    end
    module_function :timeout
  end
end
