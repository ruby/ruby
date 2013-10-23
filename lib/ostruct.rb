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
# == Examples:
#
#   require 'ostruct'
#
#   person = OpenStruct.new
#   person.name    = "John Smith"
#   person.age     = 70
#   person.pension = 300
#
#   puts person.name     # -> "John Smith"
#   puts person.age      # -> 70
#   puts person.address  # -> nil
#
# An OpenStruct employs a Hash internally to store the methods and values and
# can even be initialized with one:
#
#   australia = OpenStruct.new(:country => "Australia", :population => 20_000_000)
#   p australia   # -> <OpenStruct country="Australia" population=20000000>
#
# Hash keys with spaces or characters that would normally not be able to use for
# method calls (e.g. ()[]*) will not be immediately available on the
# OpenStruct object as a method for retrieval or assignment, but can be still be
# reached through the Object#send method.
#
#   measurements = OpenStruct.new("length (in inches)" => 24)
#   measurements.send("length (in inches)")  # -> 24
#
#   data_point = OpenStruct.new(:queued? => true)
#   data_point.queued?                       # -> true
#   data_point.send("queued?=",false)
#   data_point.queued?                       # -> false
#
# Removing the presence of a method requires the execution the delete_field
# method as setting the property value to +nil+ will not remove the method.
#
#   first_pet = OpenStruct.new(:name => 'Rowdy', :owner => 'John Smith')
#   first_pet.owner = nil
#   second_pet = OpenStruct.new(:name => 'Rowdy')
#
#   first_pet == second_pet   # -> false
#
#   first_pet.delete_field(:owner)
#   first_pet == second_pet   # -> true
#
#
# == Implementation:
#
# An OpenStruct utilizes Ruby's method lookup structure to find and define the
# necessary methods for properties. This is accomplished through the method
# method_missing and define_method.
#
# This should be a consideration if there is a concern about the performance of
# the objects that are created, as there is much more overhead in the setting
# of these properties compared to using a Hash or a Struct.
#
class OpenStruct
  #
  # Creates a new OpenStruct object.  By default, the resulting OpenStruct
  # object will have no attributes.
  #
  # The optional +hash+, if given, will generate attributes and values
  # (can be a Hash, an OpenStruct or a Struct).
  # For example:
  #
  #   require 'ostruct'
  #   hash = { "country" => "Australia", :population => 20_000_000 }
  #   data = OpenStruct.new(hash)
  #
  #   p data        # -> <OpenStruct country="Australia" population=20000000>
  #
  def initialize(hash=nil)
    @table = {}
    if hash
      hash.each_pair do |k, v|
        k = k.to_sym
        @table[k] = v
        new_ostruct_member(k)
      end
    end
  end

  # Duplicate an OpenStruct object members.
  def initialize_copy(orig)
    super
    @table = @table.dup
    @table.each_key{|key| new_ostruct_member(key)}
  end

  #
  # Converts the OpenStruct to a hash with keys representing
  # each attribute (as symbols) and their corresponding values
  # Example:
  #
  #   require 'ostruct'
  #   data = OpenStruct.new("country" => "Australia", :population => 20_000_000)
  #   data.to_h   # => {:country => "Australia", :population => 20000000 }
  #
  def to_h
    @table.dup
  end

  #
  # Yields all attributes (as a symbol) along with the corresponding values
  # or returns an enumerator if not block is given.
  # Example:
  #
  #   require 'ostruct'
  #   data = OpenStruct.new("country" => "Australia", :population => 20_000_000)
  #   data.each_pair.to_a  # => [[:country, "Australia"], [:population, 20000000]]
  #
  def each_pair
    return to_enum(__method__) { @table.size } unless block_given?
    @table.each_pair{|p| yield p}
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
    @table = x
    @table.each_key{|key| new_ostruct_member(key)}
  end

  #
  # Used internally to check if the OpenStruct is able to be
  # modified before granting access to the internal Hash table to be modified.
  #
  def modifiable
    begin
      @modifiable = true
    rescue
      raise RuntimeError, "can't modify frozen #{self.class}", caller(3)
    end
    @table
  end
  protected :modifiable

  #
  # Used internally to defined properties on the
  # OpenStruct. It does this by using the metaprogramming function
  # define_singleton_method for both the getter method and the setter method.
  #
  def new_ostruct_member(name)
    name = name.to_sym
    unless respond_to?(name)
      define_singleton_method(name) { @table[name] }
      define_singleton_method("#{name}=") { |x| modifiable[name] = x }
    end
    name
  end
  protected :new_ostruct_member

  def method_missing(mid, *args) # :nodoc:
    mname = mid.id2name
    len = args.length
    if mname.chomp!('=')
      if len != 1
        raise ArgumentError, "wrong number of arguments (#{len} for 1)", caller(1)
      end
      modifiable[new_ostruct_member(mname)] = args[0]
    elsif len == 0
      @table[mid]
    else
      err = NoMethodError.new "undefined method `#{mid}' for #{self}", mid, args
      err.set_backtrace caller(1)
      raise err
    end
  end

  # Returns the value of a member.
  #
  #   person = OpenStruct.new('name' => 'John Smith', 'age' => 70)
  #   person[:age] # => 70, same as ostruct.age
  #
  def [](name)
    @table[name.to_sym]
  end

  #
  # Sets the value of a member.
  #
  #   person = OpenStruct.new('name' => 'John Smith', 'age' => 70)
  #   person[:age] = 42 # => equivalent to ostruct.age = 42
  #   person.age # => 42
  #
  def []=(name, value)
    modifiable[new_ostruct_member(name)] = value
  end

  #
  # Remove the named field from the object. Returns the value that the field
  # contained if it was defined.
  #
  #   require 'ostruct'
  #
  #   person = OpenStruct.new('name' => 'John Smith', 'age' => 70)
  #
  #   person.delete_field('name')  # => 'John Smith'
  #
  def delete_field(name)
    sym = name.to_sym
    singleton_class.__send__(:remove_method, sym, "#{sym}=")
    @table.delete sym
  end

  InspectKey = :__inspect_key__ # :nodoc:

  #
  # Returns a string containing a detailed summary of the keys and values.
  #
  def inspect
    str = "#<#{self.class}"

    ids = (Thread.current[InspectKey] ||= [])
    if ids.include?(object_id)
      return str << ' ...>'
    end

    ids << object_id
    begin
      first = true
      for k,v in @table
        str << "," unless first
        first = false
        str << " #{k}=#{v.inspect}"
      end
      return str << '>'
    ensure
      ids.pop
    end
  end
  alias :to_s :inspect

  attr_reader :table # :nodoc:
  protected :table

  #
  # Compares this object and +other+ for equality.  An OpenStruct is equal to
  # +other+ when +other+ is an OpenStruct and the two objects' Hash tables are
  # equal.
  #
  def ==(other)
    return false unless other.kind_of?(OpenStruct)
    @table == other.table
  end

  #
  # Compares this object and +other+ for equality.  An OpenStruct is eql? to
  # +other+ when +other+ is an OpenStruct and the two objects' Hash tables are
  # eql?.
  #
  def eql?(other)
    return false unless other.kind_of?(OpenStruct)
    @table.eql?(other.table)
  end

  # Compute a hash-code for this OpenStruct.
  # Two hashes with the same content will have the same hash code
  # (and will be eql?).
  def hash
    @table.hash
  end
end
