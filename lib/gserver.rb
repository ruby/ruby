#
# Copyright (C) 2001 John W. Small All Rights Reserved
#
# Author::        John W. Small
# Documentation:: Gavin Sinclair
# Licence::       Freeware.
#
# See the class GServer for documentation.
#

require "socket"
require "thread"

#
# GServer implements a generic server, featuring thread pool management,
# simple logging, and multi-server management.  See HttpServer in 
# <tt>xmlrpc/httpserver.rb</tt> in the Ruby standard library for an example of
# GServer in action.
#
# Any kind of application-level server can be implemented using this class.
# It accepts multiple simultaneous connections from clients, up to an optional
# maximum number.  Several _services_ (i.e. one service per TCP port) can be
# run simultaneously, and stopped at any time through the class method
# <tt>GServer.stop(port)</tt>.  All the threading issues are handled, saving
# you the effort.  All events are optionally logged, but you can provide your
# own event handlers if you wish.
#
# === Example
#
# Using GServer is simple.  Below we implement a simple time server, run it,
# query it, and shut it down.  Try this code in +irb+:
#
#   require 'gserver'
#
#   #
#   # A server that returns the time in seconds since 1970.
#   # 
#   class TimeServer < GServer
#     def initialize(port=10001, *args)
#       super(port, *args)
#     end
#     def serve(io)
#       io.puts(Time.now.to_s)
#     end
#   end
#
#   # Run the server with logging enabled (it's a separate thread).
#   server = TimeServer.new
#   server.audit = true                  # Turn logging on.
#   server.start 
#
#   # *** Now point your browser to http://localhost:10001 to see it working ***
#
#   # See if it's still running. 
#   GServer.in_service?(10001)           # -> true
#   server.stopped?                      # -> false
#
#   # Shut the server down gracefully.
#   server.shutdown
#   
#   # Alternatively, stop it immediately.
#   GServer.stop(10001)
#   # or, of course, "server.stop".
#
# All the business of accepting connections and exception handling is taken
# care of.  All we have to do is implement the method that actually serves the
# client.
#
# === Advanced
#
# As the example above shows, the way to use GServer is to subclass it to
# create a specific server, overriding the +serve+ method.  You can override
# other methods as well if you wish, perhaps to collect statistics, or emit
# more detailed logging.
#
#   connecting
#   disconnecting
#   starting
#   stopping
#
# The above methods are only called if auditing is enabled.
#
# You can also override +log+ and +error+ if, for example, you wish to use a
# more sophisticated logging system.
#
class GServer

  DEFAULT_HOST = "127.0.0.1"

  def serve(io)
  end

  @@services = {}   # Hash of opened ports, i.e. services
  @@servicesMutex = Mutex.new

  def GServer.stop(port, host = DEFAULT_HOST)
    @@servicesMutex.synchronize {
      @@services[host][port].stop
    }
  end

  def GServer.in_service?(port, host = DEFAULT_HOST)
    @@services.has_key?(host) and
      @@services[host].has_key?(port)
  end

  def stop
    @connectionsMutex.synchronize  {
      if @tcpServerThread
        @tcpServerThread.raise "stop"
      end
    }
  end

  def stopped?
    @tcpServerThread == nil
  end

  def shutdown
    @shutdown = true
  end

  def connections
    @connections.size
  end

  def join
    @tcpServerThread.join if @tcpServerThread
  end

  attr_reader :port, :host, :maxConnections
  attr_accessor :stdlog, :audit, :debug

  def connecting(client)
    addr = client.peeraddr
    log("#{self.class.to_s} #{@host}:#{@port} client:#{addr[1]} " +
        "#{addr[2]}<#{addr[3]}> connect")
    true
  end

  def disconnecting(clientPort)
    log("#{self.class.to_s} #{@host}:#{@port} " +
      "client:#{clientPort} disconnect")
  end

  protected :connecting, :disconnecting

  def starting()
    log("#{self.class.to_s} #{@host}:#{@port} start")
  end

  def stopping()
    log("#{self.class.to_s} #{@host}:#{@port} stop")
  end

  protected :starting, :stopping

  def error(detail)
    log(detail.backtrace.join("\n"))
  end

  def log(msg)
    if @stdlog
      @stdlog.puts("[#{Time.new.ctime}] %s" % msg)
      @stdlog.flush
    end
  end

  protected :error, :log

  def initialize(port, host = DEFAULT_HOST, maxConnections = 4,
    stdlog = $stderr, audit = false, debug = false)
    @tcpServerThread = nil
    @port = port
    @host = host
    @maxConnections = maxConnections
    @connections = []
    @connectionsMutex = Mutex.new
    @connectionsCV = ConditionVariable.new
    @stdlog = stdlog
    @audit = audit
    @debug = debug
  end

  def start(maxConnections = -1)
    raise "running" if !stopped?
    @shutdown = false
    @maxConnections = maxConnections if maxConnections > 0
    @@servicesMutex.synchronize  {
      if GServer.in_service?(@port,@host)
        raise "Port already in use: #{host}:#{@port}!"
      end
      @tcpServer = TCPServer.new(@host,@port)
      @port = @tcpServer.addr[1]
      @@services[@host] = {} unless @@services.has_key?(@host)
      @@services[@host][@port] = self;
    }
    @tcpServerThread = Thread.new {
      begin
        starting if @audit
        while !@shutdown
          @connectionsMutex.synchronize  {
             while @connections.size >= @maxConnections
               @connectionsCV.wait(@connectionsMutex)
             end
          }
          client = @tcpServer.accept
          @connections << Thread.new(client)  { |myClient|
            begin
              myPort = myClient.peeraddr[1]
              serve(myClient) if !@audit or connecting(myClient)
            rescue => detail
              error(detail) if @debug
            ensure
              begin
                myClient.close
              rescue
              end
              @connectionsMutex.synchronize {
                @connections.delete(Thread.current)
                @connectionsCV.signal
              }
              disconnecting(myPort) if @audit
            end
          }
        end
      rescue => detail
        error(detail) if @debug
      ensure
        begin
          @tcpServer.close
        rescue
        end
        if @shutdown
          @connectionsMutex.synchronize  {
             while @connections.size > 0
               @connectionsCV.wait(@connectionsMutex)
             end
          }
        else
          @connections.each { |c| c.raise "stop" }
        end
        @tcpServerThread = nil
        @@servicesMutex.synchronize  {
          @@services[@host].delete(@port)
        }
        stopping if @audit
      end
    }
    self
  end

end
