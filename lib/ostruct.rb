# frozen_string_literal: true
#
# = ostruct.rb: OpenStruct implementation
#
# Author:: Yukihiro Matsumoto
# Documentation:: Gavin Sinclair
#
# OpenStruct allows the creation of data objects with arbitrary attributes.
# See OpenStruct for an example.
#

#
# An OpenStruct is a data structure, similar to a Hash, that allows the
# definition of arbitrary attributes with their accompanying values. This is
# accomplished by using Ruby's metaprogramming to define methods on the class
# itself.
#
# == Examples
#
#   require "ostruct"
#
#   person = OpenStruct.new
#   person.name = "John Smith"
#   person.age  = 70
#
#   person.name      # => "John Smith"
#   person.age       # => 70
#   person.address   # => nil
#
# An OpenStruct employs a Hash internally to store the attributes and values
# and can even be initialized with one:
#
#   australia = OpenStruct.new(:country => "Australia", :capital => "Canberra")
#     # => #<OpenStruct country="Australia", capital="Canberra">
#
# Hash keys with spaces or characters that could normally not be used for
# method calls (e.g. <code>()[]*</code>) will not be immediately available
# on the OpenStruct object as a method for retrieval or assignment, but can
# still be reached through the Object#send method or using [].
#
#   measurements = OpenStruct.new("length (in inches)" => 24)
#   measurements[:"length (in inches)"]       # => 24
#   measurements.send("length (in inches)")   # => 24
#
#   message = OpenStruct.new(:queued? => true)
#   message.queued?                           # => true
#   message.send("queued?=", false)
#   message.queued?                           # => false
#
# Removing the presence of an attribute requires the execution of the
# delete_field method as setting the property value to +nil+ will not
# remove the attribute.
#
#   first_pet  = OpenStruct.new(:name => "Rowdy", :owner => "John Smith")
#   second_pet = OpenStruct.new(:name => "Rowdy")
#
#   first_pet.owner = nil
#   first_pet                 # => #<OpenStruct name="Rowdy", owner=nil>
#   first_pet == second_pet   # => false
#
#   first_pet.delete_field(:owner)
#   first_pet                 # => #<OpenStruct name="Rowdy">
#   first_pet == second_pet   # => true
#
# == Caveats
#
# An OpenStruct utilizes Ruby's method lookup structure to find and define the
# necessary methods for properties. This is accomplished through the methods
# method_missing and define_singleton_method.
#
# This should be a consideration if there is a concern about the performance of
# the objects that are created, as there is much more overhead in the setting
# of these properties compared to using a Hash or a Struct.
# Creating an open struct from a small Hash and accessing a few of the
# entries can be 200 times slower than accessing the hash directly.
#
# This may also be the source of incompatibilities between Ruby versions:
#
#   o = OpenStruct.new
#   o.then # => nil in Ruby < 2.6, enumerator for Ruby >= 2.6
#
# Builtin methods may be overwritten this way, which may be a source of bugs
# or security issues:
#
#   o = OpenStruct.new
#   o.methods # => [:to_h, :marshal_load, :marshal_dump, :each_pair, ...
#   o.methods = [:foo, :bar]
#   o.methods # => [:foo, :bar]
#
# To help remedy clashes, OpenStruct uses only protected/private methods ending with `!`
# and defines aliases for builtin public methods by adding a `!`:
#
#   o = OpenStruct.new(make: 'Bentley', class: :luxury)
#   o.class # => :luxury
#   o.class! # => OpenStruct
#
# It is recommended (but not enforced) to not use fields ending in `!`.
#
# For all these reasons, consider not using OpenStruct at all.
#
class OpenStruct
  VERSION = "0.2.0"

  instance_methods.each do |method|
    new_name = "#{method}!"
    alias_method new_name, method
  end

  #
  # Creates a new OpenStruct object.  By default, the resulting OpenStruct
  # object will have no attributes.
  #
  # The optional +hash+, if given, will generate attributes and values
  # (can be a Hash, an OpenStruct or a Struct).
  # For example:
  #
  #   require "ostruct"
  #   hash = { "country" => "Australia", :capital => "Canberra" }
  #   data = OpenStruct.new(hash)
  #
  #   data   # => #<OpenStruct country="Australia", capital="Canberra">
  #
  def initialize(hash=nil)
    @table = {}
    if hash
      hash.each_pair do |k, v|
        set_ostruct_member_value!(k, v)
      end
    end
  end

  # Duplicates an OpenStruct object's Hash table.
  private def initialize_clone(orig) # :nodoc:
    super # clones the singleton class for us
    @table = @table.dup unless @table.frozen?
  end

  private def initialize_dup(orig) # :nodoc:
    super
    initialize(@table)
  end

  #
  # call-seq:
  #   ostruct.to_h                        -> hash
  #   ostruct.to_h {|name, value| block } -> hash
  #
  # Converts the OpenStruct to a hash with keys representing
  # each attribute (as symbols) and their corresponding values.
  #
  # If a block is given, the results of the block on each pair of
  # the receiver will be used as pairs.
  #
  #   require "ostruct"
  #   data = OpenStruct.new("country" => "Australia", :capital => "Canberra")
  #   data.to_h   # => {:country => "Australia", :capital => "Canberra" }
  #   data.to_h {|name, value| [name.to_s, value.upcase] }
  #               # => {"country" => "AUSTRALIA", "capital" => "CANBERRA" }
  #
  def to_h(&block)
    if block_given?
      @table.to_h(&block)
    else
      @table.dup
    end
  end

  #
  # :call-seq:
  #   ostruct.each_pair {|name, value| block }  -> ostruct
  #   ostruct.each_pair                         -> Enumerator
  #
  # Yields all attributes (as symbols) along with the corresponding values
  # or returns an enumerator if no block is given.
  #
  #   require "ostruct"
  #   data = OpenStruct.new("country" => "Australia", :capital => "Canberra")
  #   data.each_pair.to_a   # => [[:country, "Australia"], [:capital, "Canberra"]]
  #
  def each_pair
    return to_enum(__method__) { @table.size } unless block_given?
    @table.each_pair{|p| yield p}
    self
  end

  #
  # Provides marshalling support for use by the Marshal library.
  #
  def marshal_dump
    @table
  end

  #
  # Provides marshalling support for use by the Marshal library.
  #
  def marshal_load(x)
    x.each_key{|key| new_ostruct_member!(key)}
    @table = x
  end

  #
  # Used internally to defined properties on the
  # OpenStruct. It does this by using the metaprogramming function
  # define_singleton_method for both the getter method and the setter method.
  #
  def new_ostruct_member!(name) # :nodoc:
    unless @table.key?(name)
      define_singleton_method(name) { @table[name] }
      define_singleton_method("#{name}=") {|x| @table[name] = x}
    end
  end
  private :new_ostruct_member!

  def freeze
    @table.freeze
    super
  end

  private def method_missing(mid, *args) # :nodoc:
    len = args.length
    if mname = mid[/.*(?==\z)/m]
      if len != 1
        raise ArgumentError, "wrong number of arguments (given #{len}, expected 1)", caller(1)
      end
      set_ostruct_member_value!(mname, args[0])
    elsif len == 0
    elsif @table.key?(mid)
      raise ArgumentError, "wrong number of arguments (given #{len}, expected 0)"
    else
      begin
        super
      rescue NoMethodError => err
        err.backtrace.shift
        raise
      end
    end
  end

  #
  # :call-seq:
  #   ostruct[name]  -> object
  #
  # Returns the value of an attribute.
  #
  #   require "ostruct"
  #   person = OpenStruct.new("name" => "John Smith", "age" => 70)
  #   person[:age]   # => 70, same as person.age
  #
  def [](name)
    @table[name.to_sym]
  end

  #
  # :call-seq:
  #   ostruct[name] = obj  -> obj
  #
  # Sets the value of an attribute.
  #
  #   require "ostruct"
  #   person = OpenStruct.new("name" => "John Smith", "age" => 70)
  #   person[:age] = 42   # equivalent to person.age = 42
  #   person.age          # => 42
  #
  def []=(name, value)
    name = name.to_sym
    new_ostruct_member!(name)
    @table[name] = value
  end
  alias_method :set_ostruct_member_value!, :[]=
  private :set_ostruct_member_value!

  # :call-seq:
  #   ostruct.dig(name, *identifiers) -> object
  #
  # Finds and returns the object in nested objects
  # that is specified by +name+ and +identifiers+.
  # The nested objects may be instances of various classes.
  # See {Dig Methods}[rdoc-ref:doc/dig_methods.rdoc].
  #
  # Examples:
  #   require "ostruct"
  #   address = OpenStruct.new("city" => "Anytown NC", "zip" => 12345)
  #   person  = OpenStruct.new("name" => "John Smith", "address" => address)
  #   person.dig(:address, "zip") # => 12345
  #   person.dig(:business_address, "zip") # => nil
  def dig(name, *names)
    begin
      name = name.to_sym
    rescue NoMethodError
      raise TypeError, "#{name} is not a symbol nor a string"
    end
    @table.dig(name, *names)
  end

  #
  # Removes the named field from the object. Returns the value that the field
  # contained if it was defined.
  #
  #   require "ostruct"
  #
  #   person = OpenStruct.new(name: "John", age: 70, pension: 300)
  #
  #   person.delete_field("age")   # => 70
  #   person                       # => #<OpenStruct name="John", pension=300>
  #
  # Setting the value to +nil+ will not remove the attribute:
  #
  #   person.pension = nil
  #   person                 # => #<OpenStruct name="John", pension=nil>
  #
  def delete_field(name)
    sym = name.to_sym
    begin
      singleton_class.remove_method(sym, "#{sym}=")
    rescue NameError
    end
    @table.delete(sym) do
      raise NameError.new("no field `#{sym}' in #{self}", sym)
    end
  end

  InspectKey = :__inspect_key__ # :nodoc:

  #
  # Returns a string containing a detailed summary of the keys and values.
  #
  def inspect
    ids = (Thread.current[InspectKey] ||= [])
    if ids.include?(object_id)
      detail = ' ...'
    else
      ids << object_id
      begin
        detail = @table.map do |key, value|
          " #{key}=#{value.inspect}"
        end.join(',')
      ensure
        ids.pop
      end
    end
    ['#<', self.class, detail, '>'].join
  end
  alias :to_s :inspect

  attr_reader :table # :nodoc:
  protected :table
  alias table! table

  #
  # Compares this object and +other+ for equality.  An OpenStruct is equal to
  # +other+ when +other+ is an OpenStruct and the two objects' Hash tables are
  # equal.
  #
  #   require "ostruct"
  #   first_pet  = OpenStruct.new("name" => "Rowdy")
  #   second_pet = OpenStruct.new(:name  => "Rowdy")
  #   third_pet  = OpenStruct.new("name" => "Rowdy", :age => nil)
  #
  #   first_pet == second_pet   # => true
  #   first_pet == third_pet    # => false
  #
  def ==(other)
    return false unless other.kind_of?(OpenStruct)
    @table == other.table!
  end

  #
  # Compares this object and +other+ for equality.  An OpenStruct is eql? to
  # +other+ when +other+ is an OpenStruct and the two objects' Hash tables are
  # eql?.
  #
  def eql?(other)
    return false unless other.kind_of?(OpenStruct)
    @table.eql?(other.table!)
  end

  # Computes a hash code for this OpenStruct.
  # Two OpenStruct objects with the same content will have the same hash code
  # (and will compare using #eql?).
  #
  # See also Object#hash.
  def hash
    @table.hash
  end
end
