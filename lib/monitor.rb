=begin

= monitor.rb

Copyright (C) 2001  Shugo Maeda <shugo@ruby-lang.org>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

== example

This is a simple example.

  require 'monitor.rb'
  
  buf = []
  buf.extend(MonitorMixin)
  empty_cond = buf.new_cond
  
  # consumer
  Thread.start do
    loop do
      buf.synchronize do
        empty_cond.wait_while { buf.empty? }
        print buf.shift
      end
    end
  end
  
  # producer
  while line = ARGF.gets
    buf.synchronize do
      buf.push(line)
      empty_cond.signal
    end
  end

The consumer thread waits for the producer thread to push a line
to buf while buf.empty?, and the producer thread (main thread)
reads a line from ARGF and push it to buf, then call
empty_cond.signal.

=end
  

#
# Adds monitor functionality to an arbitrary object by mixing the module with
# +include+.  For example:
#
#    require 'monitor.rb'
#    
#    buf = []
#    buf.extend(MonitorMixin)
#    empty_cond = buf.new_cond
#    
#    # consumer
#    Thread.start do
#      loop do
#        buf.synchronize do
#          empty_cond.wait_while { buf.empty? }
#          print buf.shift
#        end
#      end
#    end
#    
#    # producer
#    while line = ARGF.gets
#      buf.synchronize do
#        buf.push(line)
#        empty_cond.signal
#      end
#    end
# 
# The consumer thread waits for the producer thread to push a line
# to buf while buf.empty?, and the producer thread (main thread)
# reads a line from ARGF and push it to buf, then call
# empty_cond.signal.
#
module MonitorMixin
  module Accessible
  protected
    attr_accessor :mon_owner, :mon_count
    attr_reader :mon_entering_queue, :mon_waiting_queue
  end
  
  module Initializable
  protected
    def mon_initialize
      @mon_owner = nil
      @mon_count = 0
      @mon_entering_queue = []
      @mon_waiting_queue = []
    end
  end
  
  #
  # FIXME: This isn't documented in Nutshell.
  #
  # Since MonitorMixin.new_cond returns a ConditionVariable, and the example
  # above calls while_wait and signal, this class should be documented.
  #
  class ConditionVariable
    class Timeout < Exception; end
    
    include Accessible
    
    def wait(timeout = nil)
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      
      if timeout
	ct = Thread.current
	timeout_thread = Thread.start {
	  Thread.pass
	  sleep(timeout)
	  ct.raise(Timeout.new)
	}
      end

      Thread.critical = true
      count = @monitor.mon_count
      @monitor.mon_count = 0
      @monitor.mon_owner = nil
      if @monitor.mon_waiting_queue.empty?
	t = @monitor.mon_entering_queue.shift
      else
	t = @monitor.mon_waiting_queue.shift
      end
      t.wakeup if t
      @waiters.push(Thread.current)

      begin
	Thread.stop
      rescue Timeout
      ensure
	Thread.critical = true
	if timeout && timeout_thread.alive?
	  Thread.kill(timeout_thread)
	end
	if @waiters.include?(Thread.current)  # interrupted?
	  @waiters.delete(Thread.current)
	end
	while @monitor.mon_owner &&
	    @monitor.mon_owner != Thread.current
	  @monitor.mon_waiting_queue.push(Thread.current)
	  Thread.stop
	  Thread.critical = true
	end
	@monitor.mon_owner = Thread.current
	@monitor.mon_count = count
	Thread.critical = false
      end
    end
    
    def wait_while
      while yield
	wait
      end
    end
    
    def wait_until
      until yield
	wait
      end
    end
    
    def signal
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      Thread.critical = true
      t = @waiters.shift
      t.wakeup if t
      Thread.critical = false
      Thread.pass
    end
    
    def broadcast
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      Thread.critical = true
      for t in @waiters
	t.wakeup
      end
      @waiters.clear
      Thread.critical = false
      Thread.pass
    end
    
    def count_waiters
      return @waiters.length
    end
    
  private
    def initialize(monitor)
      @monitor = monitor
      @waiters = []
    end
  end
  
  include Accessible
  include Initializable
  extend Initializable
  
  def self.extend_object(obj)
    super(obj)
    obj.mon_initialize
  end
  
  #
  # Attempts to enter exclusive section.  Returns +false+ if lock fails.
  #
  def try_mon_enter
    result = false
    Thread.critical = true
    if mon_owner.nil?
      self.mon_owner = Thread.current
    end
    if mon_owner == Thread.current
      self.mon_count += 1
      result = true
    end
    Thread.critical = false
    return result
  end

  #
  # Enters exlusive section.
  #
  def mon_enter
    Thread.critical = true
    while mon_owner != nil && mon_owner != Thread.current
      mon_entering_queue.push(Thread.current)
      Thread.stop
      Thread.critical = true
    end
    self.mon_owner = Thread.current
    self.mon_count += 1
    Thread.critical = false
  end
  
  #
  # Leaves exclusive section.
  #
  def mon_exit
    if mon_owner != Thread.current
      raise ThreadError, "current thread not owner"
    end
    Thread.critical = true
    self.mon_count -= 1
    if mon_count == 0
      self.mon_owner = nil
      if mon_waiting_queue.empty?
	t = mon_entering_queue.shift
      else
	t = mon_waiting_queue.shift
      end
    end
    t.wakeup if t
    Thread.critical = false
    Thread.pass
  end

  #
  # Enters exclusive section and executes the block.  Leaves the exclusive
  # section automatically when the block exits.  See example under
  # +MonitorMixin+.
  #
  def mon_synchronize
    mon_enter
    begin
      yield
    ensure
      mon_exit
    end
  end
  alias synchronize mon_synchronize
  
  #
  # FIXME: This isn't documented in Nutshell.
  #
  def new_cond
    return ConditionVariable.new(self)
  end
  
private
  def initialize(*args)
    super
    mon_initialize
  end
end

class Monitor
  include MonitorMixin
  alias try_enter try_mon_enter
  alias enter mon_enter
  alias exit mon_exit
  alias owner mon_owner
end


# Documentation comments:
#  - All documentation comes from Nutshell.
#  - MonitorMixin.new_cond appears in the example, but is not documented in
#    Nutshell.
#  - All the internals (internal modules Accessible and Initializable, class
#    ConditionVariable) appear in RDoc.  It might be good to hide them, by
#    making them private, or marking them :nodoc:, etc.
#  - The entire example from the RD section at the top is replicated in the RDoc
#    comment for MonitorMixin.  Does the RD section need to remain?
#  - RDoc doesn't recognise aliases, so we have mon_synchronize documented, but
#    not synchronize.
#  - mon_owner is in Nutshell, but appears as an accessor in a separate module
#    here, so is hard/impossible to RDoc.  Some other useful accessors
#    (mon_count and some queue stuff) are also in this module, and don't appear
#    directly in the RDoc output.
#  - in short, it may be worth changing the code layout in this file to make the
#    documentation easier

# Local variables:
# mode: Ruby
# tab-width: 8
# End:
