require 'monitor'
require 'thread'
require 'drb/drb'
require 'rinda/rinda'

module Rinda
  class TupleEntry
    include DRbUndumped

    def initialize(ary, sec=nil)
      @cancel = false
      @ary = make_tuple(ary)
      @renewer = nil
      renew(sec)
    end
    attr_accessor :expires

    def cancel
      @cancel = true
    end

    def alive?
      !canceled? && !expired?
    end

    def value; @ary.value; end
    def canceled?; @cancel; end
    def expired?
      return true unless @expires
      return false if @expires > Time.now
      return true if @renewer.nil?
      renew(@renewer)
      return true unless @expires
      return @expires < Time.now
    end

    def renew(sec_or_renewer)
      sec, @renewer = get_renewer(sec_or_renewer)
      @expires = make_expires(sec)
    end
    
    def make_expires(sec=nil)
      case sec
      when Numeric
	Time.now + sec
      when true
	Time.at(1)
      when nil
	Time.at(2**31-1)
      end
    end

    def [](key)
      @ary[key]
    end

    def size
      @ary.size
    end
    
    def make_tuple(ary)
      Rinda::Tuple.new(ary)
    end
    
    private
    def get_renewer(it)
      case it
      when Numeric, true, nil
	return it, nil
      else
	begin
	  return it.renew, it
	rescue Exception
	  return it, nil
	end
      end
    end
  end

  class TemplateEntry < TupleEntry
    def initialize(ary, expires=nil)
      super(ary, expires)
      @template = Rinda::Template.new(ary)
    end

    def match(tuple)
      @template.match(tuple)
    end

    def ===(tuple)
      match(tuple)
    end

    def make_tuple(ary)
      Rinda::Template.new(ary)
    end
  end

  class WaitTemplateEntry < TemplateEntry
    def initialize(place, ary, expires=nil)
      super(ary, expires)
      @place = place
      @cond = place.new_cond
      @found = nil
    end
    attr_reader :found

    def cancel
      super
      signal
    end

    def wait
      @cond.wait
    end
    
    def read(tuple)
      @found = tuple
      signal
    end
    
    def signal
      @place.synchronize do
	@cond.signal
      end
    end
  end

  class NotifyTemplateEntry < TemplateEntry
    def initialize(place, event, tuple, expires=nil)
      ary = [event, Rinda::Template.new(tuple)]
      super(ary, expires)
      @queue = Queue.new
      @done = false
    end
    
    def notify(ev)
      @queue.push(ev)
    end

    def pop
      raise RequestExpiredError if @done
      it = @queue.pop
      @done = true if it[0] == 'close'
      return it
    end
 
    def each
      while !@done
        it = pop
        yield(it)
      end
    rescue 
    ensure
      cancel
    end
  end

  class TupleBag
    def initialize
      @hash = {}
    end
    
    def push(ary)
      size = ary.size
      @hash[size] ||= []
      @hash[size].push(ary)
    end
    
    def delete(ary)
      size = ary.size
      @hash.fetch(size, []).delete(ary)
    end

    def find_all(template)
      @hash.fetch(template.size, []).find_all do |tuple|
	tuple.alive? && template.match(tuple)
      end
    end

    def find(template)
      @hash.fetch(template.size, []).find do |tuple|
	tuple.alive? && template.match(tuple)
      end
    end

    def find_all_template(tuple)
      @hash.fetch(tuple.size, []).find_all do |template|
	template.alive? && template.match(tuple)
      end
    end

    def delete_unless_alive
      deleted = []
      @hash.keys.each do |size|
	ary = []
	@hash[size].each do |tuple|
	  if tuple.alive?
	    ary.push(tuple)
	  else
	    deleted.push(tuple)
	  end
	end
	@hash[size] = ary
      end
      deleted
    end
  end

  class TupleSpace
    include DRbUndumped
    include MonitorMixin
    def initialize(timeout=60)
      super()
      @bag = TupleBag.new
      @read_waiter = TupleBag.new
      @take_waiter = TupleBag.new
      @notify_waiter = TupleBag.new
      @timeout = timeout
      @period = timeout * 2
      @keeper = keeper
    end

    def write(tuple, sec=nil)
      entry = TupleEntry.new(tuple, sec)
      synchronize do
	if entry.expired?
	  @read_waiter.find_all_template(entry).each do |template|
	    template.read(tuple)
	  end
	  notify_event('write', entry.value)
	  notify_event('delete', entry.value)
	else
	  @bag.push(entry)
	  @read_waiter.find_all_template(entry).each do |template|
	    template.read(tuple)
	  end
	  @take_waiter.find_all_template(entry).each do |template|
	    template.signal
	  end
	  notify_event('write', entry.value)
	end
      end
      entry
    end

    def take(tuple, sec=nil, &block)
      move(nil, tuple, sec, &block)
    end

    def move(port, tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, sec)
      yield(template) if block_given?
      synchronize do
	entry = @bag.find(template)
	if entry
	  port.push(entry.value) if port
	  @bag.delete(entry)
	  notify_event('take', entry.value)
	  return entry.value
	end
        raise RequestExpiredError if template.expired?

	begin
	  @take_waiter.push(template)
	  while true
	    raise RequestCanceledError if template.canceled?
	    raise RequestExpiredError if template.expired?
	    entry = @bag.find(template)
	    if entry
	      port.push(entry.value) if port
	      @bag.delete(entry)
	      notify_event('take', entry.value)
	      return entry.value
	    end
	    template.wait
	  end
	ensure
	  @take_waiter.delete(template)
	end
      end
    end

    def read(tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, sec)
      yield(template) if block_given?
      synchronize do
	entry = @bag.find(template)
	return entry.value if entry
        raise RequestExpiredError if template.expired?

	begin
	  @read_waiter.push(template)
	  template.wait
	  raise RequestCanceledError if template.canceled?
	  raise RequestExpiredError if template.expired?
	  return template.found
	ensure
	  @read_waiter.delete(template)
	end
      end
    end

    def read_all(tuple)
      template = WaitTemplateEntry.new(self, tuple, nil)
      synchronize do
	entry = @bag.find_all(template)
	entry.collect do |e|
	  e.value
	end
      end
    end

    def notify(event, tuple, sec=nil)
      template = NotifyTemplateEntry.new(self, event, tuple, sec)
      synchronize do
	@notify_waiter.push(template)
      end
      template
    end
    
    private
    def keep_clean
      synchronize do
	@read_waiter.delete_unless_alive.each do |e|
	  e.signal
	end
	@take_waiter.delete_unless_alive.each do |e|
	  e.signal
	end
	@notify_waiter.delete_unless_alive.each do |e|
	  e.notify(['close'])
	end
	@bag.delete_unless_alive.each do |e|
	  notify_event('delete', e.value)
	end
      end
    end
    
    def notify_event(event, tuple)
      ev = [event, tuple]
      @notify_waiter.find_all_template(ev).each do |template|
	template.notify(ev)
      end
    end

    def keeper
      Thread.new do
	loop do
	  sleep(@period)
	  keep_clean
	end
      end
    end
  end
end
