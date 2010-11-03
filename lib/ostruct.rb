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
# OpenStruct allows you to create data objects and set arbitrary attributes.
# For example:
#
#   require 'ostruct'
#
#   record = OpenStruct.new
#   record.name    = "John Smith"
#   record.age     = 70
#   record.pension = 300
#
#   puts record.name     # -> "John Smith"
#   puts record.address  # -> nil
#
# It is like a hash with a different way to access the data.  In fact, it is
# implemented with a hash, and you can initialize it with one.
#
#   hash = { "country" => "Australia", :population => 20_000_000 }
#   data = OpenStruct.new(hash)
#
#   p data        # -> <OpenStruct country="Australia" population=20000000>
#
class OpenStruct
  #
  # Create a new OpenStruct object.  The optional +hash+, if given, will
  # generate attributes and values.  For example.
  #
  #   require 'ostruct'
  #   hash = { "country" => "Australia", :population => 20_000_000 }
  #   data = OpenStruct.new(hash)
  #
  #   p data        # -> <OpenStruct country="Australia" population=20000000>
  #
  # By default, the resulting OpenStruct object will have no attributes.
  #
  def initialize(hash=nil)
    @table = {}
    if hash
      for k,v in hash
        @table[k.to_sym] = v
        new_ostruct_member(k)
      end
    end
  end

  # Duplicate an OpenStruct object members.
  def initialize_copy(orig)
    super
    @table = @table.dup
  end

  def marshal_dump
    @table
  end
  def marshal_load(x)
    @table = x
    @table.each_key{|key| new_ostruct_member(key)}
  end

  def modifiable
    begin
      @modifiable = true
    rescue
      raise TypeError, "can't modify frozen #{self.class}", caller(3)
    end
    @table
  end
  protected :modifiable

  def new_ostruct_member(name)
    name = name.to_sym
    unless self.respond_to?(name)
      class << self; self; end.class_eval do
        define_method(name) { @table[name] }
        define_method("#{name}=") { |x| modifiable[name] = x }
      end
    end
    name
  end

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
      raise NoMethodError, "undefined method `#{mname}' for #{self}", caller(1)
    end
  end

  #
  # Remove the named field from the object.
  #
  def delete_field(name)
    sym = name.to_sym
    @table.delete sym
    singleton_class.__send__(:remove_method, sym, "#{name}=")
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
  # Compare this object and +other+ for equality.
  #
  def ==(other)
    return false unless(other.kind_of?(OpenStruct))
    return @table == other.table
  end
end
