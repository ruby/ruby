#
# rinda.rb: A Ruby implementation of the Linda distibuted computing paradigm.
#
# <i>Introduction to Linda/rinda?</i>
#
# <i>Why is this library separate from <tt>drb</tt>?</i> 
#
# <i>Example(s)</i> 
#
# (See the samples directory in the Ruby distribution, from 1.8.2 onwards.)
#

require 'drb/drb'
require 'thread'

#
# A module to implement the Linda programming paradigm in Ruby.
# This is part of +drb+ (dRuby).
#
module Rinda
  class RequestCanceledError < ThreadError; end
  class RequestExpiredError < ThreadError; end

  #
  # A tuple is the elementary object in Rinda programming.
  # Tuples may be matched against templates if the tuple and
  # the template are the same size.
  #
  class Tuple
    # Initialize a tuple with an Array or a Hash.
    def initialize(ary_or_hash)
      if Hash === ary_or_hash
	init_with_hash(ary_or_hash)
      else
	init_with_ary(ary_or_hash)
      end
    end

    # The number of elements in the tuple.
    def size
      @tuple.size
    end

    # Accessor method for elements of the tuple.
    def [](k)
      @tuple[k]
    end

    # Iterate through the tuple, yielding the index or key, and the
    # value, thus ensuring arrays are iterated similarly to hashes.
    def each # FIXME
      if Hash === @tuple
	@tuple.each { |k, v| yield(k, v) }
      else
	@tuple.each_with_index { |v, k| yield(k, v) }
      end
    end

    # Return the tuple itself -- i.e the Array or hash.
    def value
      @tuple
    end

    private
    def init_with_ary(ary)
      @tuple_size = ary.size
      @tuple = Array.new(@tuple_size)
      @tuple.size.times do |i|
	@tuple[i] = ary[i]
      end
    end

    def init_with_hash(hash)
      @tuple_size = hash[:size]
      @tuple = Hash.new
      hash.each do |k, v|
	next unless String === k
	@tuple[k] = v
      end
    end
  end

  #
  # Templates are used to match tuples in Rinda.
  #
  class Template < Tuple
    # Perform the matching of a tuple against a template.  An
    # element with a +nil+ value in a template acts as a wildcard,
    # matching any value in the corresponding position in the tuple.
    def match(tuple)
      return false unless tuple.respond_to?(:size)
      return false unless tuple.respond_to?(:[])
      return false if @tuple_size && (@tuple_size != tuple.size)
      each do |k, v|
	next if v.nil?
	return false unless (v === tuple[k] rescue false)
      end
      return true
    end
    
    # Alias for #match.
    def ===(tuple)
      match(tuple)
    end
  end
  
  #
  # <i>Documentation?</i>
  #
  class DRbObjectTemplate
    def initialize(uri=nil, ref=nil)
      @drb_uri = uri
      @drb_ref = ref
    end
    
    def ===(ro)
      return true if super(ro)
      unless @drb_uri.nil?
	return false unless (@drb_uri === ro.__drburi rescue false)
      end
      unless @drb_ref.nil?
	return false unless (@drb_ref === ro.__drbref rescue false)
      end
      true
    end
  end

  #
  # TupleSpaceProxy allows a remote Tuplespace to appear as local.
  #
  class TupleSpaceProxy
    def initialize(ts)
      @ts = ts
    end
    
    def write(tuple, sec=nil)
      @ts.write(tuple, sec)
    end
    
    def take(tuple, sec=nil, &block)
      port = []
      @ts.move(DRbObject.new(port), tuple, sec, &block)
      port[0]
    end
    
    def read(tuple, sec=nil, &block)
      @ts.read(tuple, sec, &block)
    end
    
    def read_all(tuple)
      @ts.read_all(tuple)
    end
    
    def notify(ev, tuple, sec=nil)
      @ts.notify(ev, tuple, sec)
    end
  end

  #
  # <i>Documentation?</i>
  #
  class SimpleRenewer
    include DRbUndumped
    def initialize(sec=180)
      @sec = sec
    end

    def renew
      @sec
    end
  end
end

