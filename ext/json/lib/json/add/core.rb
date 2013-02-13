# This file contains implementations of ruby core's custom objects for
# serialisation/deserialisation.

unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end
require 'date'

# Symbol serialization/deserialization
class Symbol
  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      's'            => to_s,
    }
  end

  # Stores class name (Symbol) with String representation of Symbol as a JSON string.
  def to_json(*a)
    as_json.to_json(*a)
  end

  # Deserializes JSON string by converting the <tt>string</tt> value stored in the object to a Symbol
  def self.json_create(o)
    o['s'].to_sym
  end
end

# Time serialization/deserialization
class Time

  # Deserializes JSON string by converting time since epoch to Time
  def self.json_create(object)
    if usec = object.delete('u') # used to be tv_usec -> tv_nsec
      object['n'] = usec * 1000
    end
    if instance_methods.include?(:tv_nsec)
      at(object['s'], Rational(object['n'], 1000))
    else
      at(object['s'], object['n'] / 1000)
    end
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    nanoseconds = [ tv_usec * 1000 ]
    respond_to?(:tv_nsec) and nanoseconds << tv_nsec
    nanoseconds = nanoseconds.max
    {
      JSON.create_id => self.class.name,
      's'            => tv_sec,
      'n'            => nanoseconds,
    }
  end

  # Stores class name (Time) with number of seconds since epoch and number of
  # microseconds for Time as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# Date serialization/deserialization
class Date

  # Deserializes JSON string by converting Julian year <tt>y</tt>, month
  # <tt>m</tt>, day <tt>d</tt> and Day of Calendar Reform <tt>sg</tt> to Date.
  def self.json_create(object)
    civil(*object.values_at('y', 'm', 'd', 'sg'))
  end

  alias start sg unless method_defined?(:start)

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'y' => year,
      'm' => month,
      'd' => day,
      'sg' => start,
    }
  end

  # Stores class name (Date) with Julian year <tt>y</tt>, month <tt>m</tt>, day
  # <tt>d</tt> and Day of Calendar Reform <tt>sg</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# DateTime serialization/deserialization
class DateTime

  # Deserializes JSON string by converting year <tt>y</tt>, month <tt>m</tt>,
  # day <tt>d</tt>, hour <tt>H</tt>, minute <tt>M</tt>, second <tt>S</tt>,
  # offset <tt>of</tt> and Day of Calendar Reform <tt>sg</tt> to DateTime.
  def self.json_create(object)
    args = object.values_at('y', 'm', 'd', 'H', 'M', 'S')
    of_a, of_b = object['of'].split('/')
    if of_b and of_b != '0'
      args << Rational(of_a.to_i, of_b.to_i)
    else
      args << of_a
    end
    args << object['sg']
    civil(*args)
  end

  alias start sg unless method_defined?(:start)

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'y' => year,
      'm' => month,
      'd' => day,
      'H' => hour,
      'M' => min,
      'S' => sec,
      'of' => offset.to_s,
      'sg' => start,
    }
  end

  # Stores class name (DateTime) with Julian year <tt>y</tt>, month <tt>m</tt>,
  # day <tt>d</tt>, hour <tt>H</tt>, minute <tt>M</tt>, second <tt>S</tt>,
  # offset <tt>of</tt> and Day of Calendar Reform <tt>sg</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# Range serialization/deserialization
class Range

  # Deserializes JSON string by constructing new Range object with arguments
  # <tt>a</tt> serialized by <tt>to_json</tt>.
  def self.json_create(object)
    new(*object['a'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id  => self.class.name,
      'a'             => [ first, last, exclude_end? ]
    }
  end

  # Stores class name (Range) with JSON array of arguments <tt>a</tt> which
  # include <tt>first</tt> (integer), <tt>last</tt> (integer), and
  # <tt>exclude_end?</tt> (boolean) as JSON string.
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# Struct serialization/deserialization
class Struct

  # Deserializes JSON string by constructing new Struct object with values
  # <tt>v</tt> serialized by <tt>to_json</tt>.
  def self.json_create(object)
    new(*object['v'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    klass = self.class.name
    klass.to_s.empty? and raise JSON::JSONError, "Only named structs are supported!"
    {
      JSON.create_id => klass,
      'v'            => values,
    }
  end

  # Stores class name (Struct) with Struct values <tt>v</tt> as a JSON string.
  # Only named structs are supported.
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# Exception serialization/deserialization
class Exception

  # Deserializes JSON string by constructing new Exception object with message
  # <tt>m</tt> and backtrace <tt>b</tt> serialized with <tt>to_json</tt>
  def self.json_create(object)
    result = new(object['m'])
    result.set_backtrace object['b']
    result
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'm'            => message,
      'b'            => backtrace,
    }
  end

  # Stores class name (Exception) with message <tt>m</tt> and backtrace array
  # <tt>b</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end

# Regexp serialization/deserialization
class Regexp

  # Deserializes JSON string by constructing new Regexp object with source
  # <tt>s</tt> (Regexp or String) and options <tt>o</tt> serialized by
  # <tt>to_json</tt>
  def self.json_create(object)
    new(object['s'], object['o'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'o'            => options,
      's'            => source,
    }
  end

  # Stores class name (Regexp) with options <tt>o</tt> and source <tt>s</tt>
  # (Regexp or String) as JSON string
  def to_json(*)
    as_json.to_json
  end
end
