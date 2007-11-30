# This file contains implementations of ruby core's custom objects for
# serialisation/deserialisation.

unless Object.const_defined?(:JSON) and ::JSON.const_defined?(:JSON_LOADED) and
  ::JSON::JSON_LOADED
  require 'json'
end
require 'date'

class Time
  def self.json_create(object)
    at(*object.values_at('s', 'u'))
  end

  def to_json(*args)
    {
      'json_class' => self.class.name.to_s,
      's' => tv_sec,
      'u' => tv_usec,
    }.to_json(*args)
  end
end

class Date
  def self.json_create(object)
    civil(*object.values_at('y', 'm', 'd', 'sg'))
  end

  def to_json(*args)
    {
      'json_class' => self.class.name.to_s,
      'y' => year,
      'm' => month,
      'd' => day,
      'sg' => @sg,
    }.to_json(*args)
  end
end

class DateTime
  def self.json_create(object)
    args = object.values_at('y', 'm', 'd', 'H', 'M', 'S')
    of_a, of_b = object['of'].split('/')
    args << Rational(of_a.to_i, of_b.to_i)
    args << object['sg']
    civil(*args)
  end

  def to_json(*args)
    {
      'json_class' => self.class.name.to_s,
      'y' => year,
      'm' => month,
      'd' => day,
      'H' => hour,
      'M' => min,
      'S' => sec,
      'of' => offset.to_s,
      'sg' => @sg,
    }.to_json(*args)
  end
end

class Range
  def self.json_create(object)
    new(*object['a'])
  end

  def to_json(*args)
    {
      'json_class'   => self.class.name.to_s,
      'a'         => [ first, last, exclude_end? ]
    }.to_json(*args)
  end
end

class Struct
  def self.json_create(object)
    new(*object['v'])
  end

  def to_json(*args)
    klass = self.class.name.to_s
    klass.empty? and raise JSON::JSONError, "Only named structs are supported!"
    {
      'json_class' => klass,
      'v'     => values,
    }.to_json(*args)
  end
end

class Exception
  def self.json_create(object)
    result = new(object['m'])
    result.set_backtrace object['b']
    result
  end

  def to_json(*args)
    {
      'json_class' => self.class.name.to_s,
      'm'   => message,
      'b' => backtrace,
    }.to_json(*args)
  end
end

class Regexp
  def self.json_create(object)
    new(object['s'], object['o'])
  end

  def to_json(*)
    {
      'json_class' => self.class.name.to_s,
      'o' => options,
      's' => source,
    }.to_json
  end
end
