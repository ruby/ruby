#
# = tuplespace: <i>???</i>
#
# <i>Overview of rinda/tuplespace.rb</i> 
#
# <i>Example(s)</i> 
#

require 'monitor'
require 'thread'
require 'drb/drb'
require 'rinda/rinda'

module Rinda
  #
  # A TupleEntry is a Tuple (i.e. a possible entry in some Tuplespace)
  # together with expiry and cancellation data.
  #
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

    # Return the object which makes up the tuple itself: the Array
    # or Hash.
    def value; @ary.value; end

    def canceled?; @cancel; end

    # Has this tuple expired? (true/false).
    def expired?
      return true unless @expires
      return false if @expires > Time.now
      return true if @renewer.nil?
      renew(@renewer)
      return true unless @expires
      return @expires < Time.now
    end

    # Reset the expiry data according to the supplied argument. If
    # the argument is:
    #
    # +nil+::    it is set to expire in the far future.
    # +false+::  it has expired.
    # Numeric::  it will expire in that many seconds.
    #
    # Otherwise the argument refers to some kind of renewer object
    # which will reset its expiry time. 
    def renew(sec_or_renewer)
      sec, @renewer = get_renewer(sec_or_renewer)
      @expires = make_expires(sec)
    end

    # Create an expiry time. Called with:
    #
    # +true+:: the expiry time is the start of 1970 (i.e. expired).
    # +nil+::  it is  Tue Jan 19 03:14:07 GMT Standard Time 2038 (i.e. when
    #          UNIX clocks will die)
    #
    # otherwise it is +sec+ seconds into the
    # future.
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

    # Accessor method for the tuple.
    def [](key)
      @ary[key]
    end

    def fetch(key)
      @ary.fetch(key)
    end

    # The size of the tuple.
    def size
      @ary.size
    end

    # Create a new tuple from the supplied object (array-like).
    def make_tuple(ary)
      Rinda::Tuple.new(ary)
    end

    private
    # Given +true+, +nil+, or +Numeric+, returns that (suitable input to
    # make_expires) and +nil+ (no actual +renewer+), else it return the
    # time data from the supplied +renewer+.
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

  #
  # The same as a TupleEntry but with methods to do matching.
  #
  class TemplateEntry < TupleEntry
    def initialize(ary, expires=nil)
      super(ary, expires)
      @template = Rinda::Template.new(ary)
    end

    def match(tuple)
      @template.match(tuple)
    end

    # An alias for #match.
    def ===(tuple)
      match(tuple)
    end

    # Create a new Template from the supplied object.
    def make_tuple(ary)
      Rinda::Template.new(ary)
    end
  end

  #
  # <i>Documentation?</i>
  #
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

  #
  # <i>Documentation?</i>
  #
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

  #
  # TupleBag is an unordered collection of tuples. It is the basis
  # of Tuplespace.
  # 
  class TupleBag
    def initialize
      @hash = {}
    end

    def has_expires?
      @hash.each do |k, v|
        v.each do |tuple|
          return true if tuple.expires
        end
      end
      false
    end

    # Add the object to the TupleBag.
    def push(ary)
      size = ary.size
      @hash[size] ||= []
      @hash[size].push(ary)
    end

    # Remove the object from the TupleBag.
    def delete(ary)
      size = ary.size
      @hash.fetch(size, []).delete(ary)
    end

    # Finds all tuples that match the template and are alive.
    def find_all(template)
      @hash.fetch(template.size, []).find_all do |tuple|
	tuple.alive? && template.match(tuple)
      end
    end

    # Finds a template that matches and is alive.
    def find(template)
      @hash.fetch(template.size, []).find do |tuple|
	tuple.alive? && template.match(tuple)
      end
    end

    # Finds all tuples in the TupleBag which when treated as
    # templates, match the supplied tuple and are alive.
    def find_all_template(tuple)
      @hash.fetch(tuple.size, []).find_all do |template|
	template.alive? && template.match(tuple)
      end
    end

    # Delete tuples which are not alive from the TupleBag. Returns
    # the list of tuples so deleted.
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

  # 
  # The Tuplespace manages access to the tuples it contains,
  # ensuring mutual exclusion requirements are met.
  #
  class TupleSpace
    include DRbUndumped
    include MonitorMixin
    def initialize(period=60)
      super()
      @bag = TupleBag.new
      @read_waiter = TupleBag.new
      @take_waiter = TupleBag.new
      @notify_waiter = TupleBag.new
      @period = period
      @keeper = nil
    end

    # Put a tuple into the tuplespace.
    def write(tuple, sec=nil)
      entry = TupleEntry.new(tuple, sec)
      start_keeper
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

    # Remove an entry from the Tuplespace.
    def take(tuple, sec=nil, &block)
      move(nil, tuple, sec, &block)
    end

    def move(port, tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, sec)
      yield(template) if block_given?
      start_keeper
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
      start_keeper
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

    def start_keeper
      return if @keeper && @keeper.alive?
      @keeper = Thread.new do
        while need_keeper?
          keep_clean
          sleep(@period)
	end
      end
    end

    def need_keeper?
      return true if @bag.has_expires?
      return true if @read_waiter.has_expires?
      return true if @take_waiter.has_expires?
      return true if @notify_waiter.has_expires?
    end
  end
end
