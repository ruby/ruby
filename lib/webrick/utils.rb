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
require 'io/nonblock'
require 'etc'

module WEBrick
  module Utils
    ##
    # Sets IO operations on +io+ to be non-blocking
    def set_non_blocking(io)
      io.nonblock = true if io.respond_to?(:nonblock=)
    end
    module_function :set_non_blocking

    ##
    # Sets the close on exec flag for +io+
    def set_close_on_exec(io)
      io.close_on_exec = true if io.respond_to?(:close_on_exec=)
    end
    module_function :set_close_on_exec

    ##
    # Changes the process's uid and gid to the ones of +user+
    def su(user)
      if pw = Etc.getpwnam(user)
        Process::initgroups(user, pw.gid)
        Process::Sys::setgid(pw.gid)
        Process::Sys::setuid(pw.uid)
      else
        warn("WEBrick::Utils::su doesn't work on this platform")
      end
    end
    module_function :su

    ##
    # The server hostname
    def getservername
      host = Socket::gethostname
      begin
        Socket::gethostbyname(host)[0]
      rescue
        host
      end
    end
    module_function :getservername

    ##
    # Creates TCP server sockets bound to +address+:+port+ and returns them.
    #
    # It will create IPV4 and IPV6 sockets on all interfaces.
    def create_listeners(address, port)
      unless port
        raise ArgumentError, "must specify port"
      end
      sockets = Socket.tcp_server_sockets(address, port)
      sockets = sockets.map {|s|
        s.autoclose = false
        ts = TCPServer.for_fd(s.fileno)
        s.close
        ts
      }
      return sockets
    end
    module_function :create_listeners

    ##
    # Characters used to generate random strings
    RAND_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                 "0123456789" +
                 "abcdefghijklmnopqrstuvwxyz"

    ##
    # Generates a random string of length +len+
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

    ##
    # Class used to manage timeout handlers across multiple threads.
    #
    # Timeout handlers should be managed by using the class methods which are
    # synchronized.
    #
    #   id = TimeoutHandler.register(10, Timeout::Error)
    #   begin
    #     sleep 20
    #     puts 'foo'
    #   ensure
    #     TimeoutHandler.cancel(id)
    #   end
    #
    # will raise Timeout::Error
    #
    #   id = TimeoutHandler.register(10, Timeout::Error)
    #   begin
    #     sleep 5
    #     puts 'foo'
    #   ensure
    #     TimeoutHandler.cancel(id)
    #   end
    #
    # will print 'foo'
    #
    class TimeoutHandler
      include Singleton

      class Thread < ::Thread; end

      ##
      # Mutex used to synchronize access across threads
      TimeoutMutex = Mutex.new # :nodoc:

      ##
      # Registers a new timeout handler
      #
      # +time+:: Timeout in seconds
      # +exception+:: Exception to raise when timeout elapsed
      def TimeoutHandler.register(seconds, exception)
        TimeoutMutex.synchronize{
          instance.register(Thread.current, Time.now + seconds, exception)
        }
      end

      ##
      # Cancels the timeout handler +id+
      def TimeoutHandler.cancel(id)
        TimeoutMutex.synchronize{
          instance.cancel(Thread.current, id)
        }
      end

      ##
      # Creates a new TimeoutHandler.  You should use ::register and ::cancel
      # instead of creating the timeout handler directly.
      def initialize
        @timeout_info = Hash.new
        @watcher = Thread.start{
          while true
            now = Time.now
            wakeup = nil
            @timeout_info.each {|thread, ary|
              next unless ary
              ary.dup.each{|info|
                time, exception = *info
                if time < now
                  interrupt(thread, info.object_id, exception)
                elsif !wakeup || time < wakeup
                  wakeup = time
                end
              }
            }
            if !wakeup
              sleep
            elsif (wakeup -= now) > 0
              sleep(wakeup)
            end
          end
        }
      end

      ##
      # Interrupts the timeout handler +id+ and raises +exception+
      def interrupt(thread, id, exception)
        TimeoutMutex.synchronize{
          if cancel(thread, id) && thread.alive?
            thread.raise(exception, "execution timeout")
          end
        }
      end

      ##
      # Registers a new timeout handler
      #
      # +time+:: Timeout in seconds
      # +exception+:: Exception to raise when timeout elapsed
      def register(thread, time, exception)
        @timeout_info[thread] ||= Array.new
        @timeout_info[thread] << (info = [time, exception])
        begin
          @watcher.wakeup
        rescue ThreadError
        end
        return info.object_id
      end

      ##
      # Cancels the timeout handler +id+
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

    ##
    # Executes the passed block and raises +exception+ if execution takes more
    # than +seconds+.
    #
    # If +seconds+ is zero or nil, simply executes the block
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
