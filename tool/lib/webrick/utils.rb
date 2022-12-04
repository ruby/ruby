# frozen_string_literal: false
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
        warn("WEBrick::Utils::su doesn't work on this platform", uplevel: 1)
      end
    end
    module_function :su

    ##
    # The server hostname
    def getservername
      Socket::gethostname
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

      ##
      # Mutex used to synchronize access across threads
      TimeoutMutex = Thread::Mutex.new # :nodoc:

      ##
      # Registers a new timeout handler
      #
      # +time+:: Timeout in seconds
      # +exception+:: Exception to raise when timeout elapsed
      def TimeoutHandler.register(seconds, exception)
        at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        instance.register(Thread.current, at, exception)
      end

      ##
      # Cancels the timeout handler +id+
      def TimeoutHandler.cancel(id)
        instance.cancel(Thread.current, id)
      end

      def self.terminate
        instance.terminate
      end

      ##
      # Creates a new TimeoutHandler.  You should use ::register and ::cancel
      # instead of creating the timeout handler directly.
      def initialize
        TimeoutMutex.synchronize{
          @timeout_info = Hash.new
        }
        @queue = Thread::Queue.new
        @watcher = nil
      end

      # :nodoc:
      private \
        def watch
          to_interrupt = []
          while true
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            wakeup = nil
            to_interrupt.clear
            TimeoutMutex.synchronize{
              @timeout_info.each {|thread, ary|
                next unless ary
                ary.each{|info|
                  time, exception = *info
                  if time < now
                    to_interrupt.push [thread, info.object_id, exception]
                  elsif !wakeup || time < wakeup
                    wakeup = time
                  end
                }
              }
            }
            to_interrupt.each {|arg| interrupt(*arg)}
            if !wakeup
              @queue.pop
            elsif (wakeup -= now) > 0
              begin
                (th = Thread.start {@queue.pop}).join(wakeup)
              ensure
                th&.kill&.join
              end
            end
            @queue.clear
          end
        end

      # :nodoc:
      private \
        def watcher
          (w = @watcher)&.alive? and return w # usual case
          TimeoutMutex.synchronize{
            (w = @watcher)&.alive? and next w # pathological check
            @watcher = Thread.start(&method(:watch))
          }
        end

      ##
      # Interrupts the timeout handler +id+ and raises +exception+
      def interrupt(thread, id, exception)
        if cancel(thread, id) && thread.alive?
          thread.raise(exception, "execution timeout")
        end
      end

      ##
      # Registers a new timeout handler
      #
      # +time+:: Timeout in seconds
      # +exception+:: Exception to raise when timeout elapsed
      def register(thread, time, exception)
        info = nil
        TimeoutMutex.synchronize{
          (@timeout_info[thread] ||= []) << (info = [time, exception])
        }
        @queue.push nil
        watcher
        return info.object_id
      end

      ##
      # Cancels the timeout handler +id+
      def cancel(thread, id)
        TimeoutMutex.synchronize{
          if ary = @timeout_info[thread]
            ary.delete_if{|info| info.object_id == id }
            if ary.empty?
              @timeout_info.delete(thread)
            end
            return true
          end
          return false
        }
      end

      ##
      def terminate
        TimeoutMutex.synchronize{
          @timeout_info.clear
          @watcher&.kill&.join
        }
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
