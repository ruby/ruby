=begin
 external service manager
 	Copyright (c) 2000 Masatoshi SEKI 
=end

require 'drb/drb'
require 'thread'

module DRb
  class ExtServManager
    include DRbUndumped

    @@command = {}

    def self.command
      @@command
    end

    def self.command=(cmd)
      @@command = cmd
    end
      
    def initialize
      @servers = {}
      @waiting = []
      @queue = Queue.new
      @thread = invoke_thread
      @uri = nil
    end
    attr_accessor :uri

    def service(name)
      while true
	server = nil
	Thread.exclusive do
	  server = @servers[name] if @servers[name]
	end
	return server if server && server.alive?
	invoke_service(name)
      end
    end

    def regist(name, ro)
      ary = nil
      Thread.exclusive do
	@servers[name] = ro
	ary = @waiting
	@waiting = []
      end
      ary.each do |th|
	begin
	  th.run
	rescue ThreadError
	end
      end
      self
    end
    
    def unregist(name)
      Thread.exclusive do
	@servers.delete(name)
      end
    end

    private
    def invoke_thread
      Thread.new do
	while true
	  name = @queue.pop
	  invoke_service_command(name, @@command[name])
	end
      end
    end

    def invoke_service(name)
      Thread.critical = true
      @waiting.push Thread.current
      @queue.push name
      Thread.stop
    end

    def invoke_service_command(name, command)
      raise "invalid command. name: #{name}" unless command
      Thread.exclusive do
	return if @servers.include?(name)
	@servers[name] = false
      end
      uri = @uri || DRb.uri
      if RUBY_PLATFORM =~ /mswin32/
	system("cmd /c start /b #{command} #{uri} #{name}")
      else
	system("#{command} #{uri} #{name} &")
      end
    end
  end
end
