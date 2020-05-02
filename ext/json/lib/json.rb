#frozen_string_literal: false
require 'json/common'

##
# = JavaScript \Object Notation (\JSON)
#
# \JSON is a lightweight data-interchange format.
#
# A \JSON value is one of the following:
# - Double-quoted text:  <tt>"foo"</tt>.
# - Number:  +1+, +1.0+, +2.0e2+.
# - Boolean:  +true+, +false+.
# - Null: +null+.
# - \Array: an ordered list of values, enclosed by square brackets:
#
#     ["foo", 1, 1.0, 2.0e2, true, false, null]
#
# - \Object: a collection of name/value pairs, enclosed by curly braces;
#   each name is double-quoted text;
#   the values may be any \JSON values:
#
#     {"a": "foo", "b": 1, "c": 1.0, "d": 2.0e2, "e": true, "f": false, "g": null}
#
#
# \JSON arrays and objects may be nested (to any depth):
#   {"foo": {"bar": 1, "baz": 2}, "bat": [0, 1, 2]}
#   [{"foo": 0, "bar": 1}, ["baz", 2]]
#
# To read more about \JSON visit: http://json.org
#
# == Using \Module \JSON
#
# To make module \JSON available in your code, begin with:
#   require 'json'
#
# All examples here assume that this has been done.
#
# === Parsing \JSON
#
# You can parse a \String containing \JSON data using
# either method JSON.parse or JSON.parse!.
#
# The difference between the two methods
# is that JSON.parse! takes some performance shortcuts
# that may not be safe in all cases;
# use it only for data from trusted sources.
# Use the safer method JSON.parse for less trusted sources.
#
# ==== Parsing a \JSON \Array
#
# When the \JSON source is an array, JSON.parse by default returns a new Ruby \Array:
#   source = '["foo", 1, 1.0, 2.0e2, true, false, null]'
#   a = JSON.parse(source)
#   a # => ["foo", 1, 1.0, 200.0, true, false, nil]
#   a.class # => Array
#
# The \JSON array may contain nested arrays and objects:
#   source = '[{"foo": 0, "bar": 1}, ["baz", 2]]'
#   JSON.parse(source) # => [{"foo"=>0, "bar"=>1}, ["baz", 2]]
#
# ==== Parsing a \JSON \Object
#
# When the \JSON source is an object, JSON.parse by default returns a new Ruby \Hash:
#   source = '{"a": "foo", "b": 1, "c": 1.0, "d": 2.0e2, "e": true, "f": false, "g": null}'
#   h = JSON.parse(source)
#   h # => {"a"=>"foo", "b"=>1, "c"=>1.0, "d"=>200.0, "e"=>true, "f"=>false, "g"=>nil}
#   h.class # => Hash
#
# The \JSON object may contain nested arrays and objects:
#   source = '{"foo": {"bar": 1, "baz": 2}, "bat": [0, 1, 2]}'
#   JSON.parse(source) # => {"foo"=>{"bar"=>1, "baz"=>2}, "bat"=>[0, 1, 2]}
#
# ==== Parsing \JSON Scalars
#
# When the \JSON source is a bare scalar (not an array or object),
# JSON.parse returns a scalar.
#
# \String:
#   s = JSON.parse('"foo"')
#   s # => "foo"
#   s.class # => String
# \Integer:
#   n = JSON.parse('1')
#   n # => 1
#   n.class # => Integer
# \Float:
#   f = JSON.parse('1.0')
#   f # => 1.0
#   f.class # => Float
#   f = JSON.parse('2.0e2')
#   f # => 200
#   f.class # => Float
# Boolean:
#   b = JSON.parse('true')
#   b # => true
#   b.class # => TrueClass
#   b = JSON.parse('false')
#   b # => false
#   b.class # => FalseClass
# Null:
#   n = JSON.parse('null')
#   n # => nil
#   n.class # => NilClass
#
# ==== Parsing Options
#
# Argument +opts+ is a \Hash object containing options for parsing.
#
# ---
#
# Option +:max_nesting+ specifies the maximum nesting depth allowed;
# defaults to +100+; specify +false+ to disable depth checking.
#
# With the default:
#   source = '[0, [1, [2, [3]]]]'
#   a = JSON.parse(source)
#   a # => [0, [1, [2, [3]]]]
# Too deep:
#   # Raises JSON::NestingError (nesting of 2 is too deep):
#   a = JSON.parse(source, {max_nesting: 1})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Fixnum)):
#   JSON.parse(source, {max_nesting: :foo})
#
# ---
#
# Option +allow_nan+ specifies whether to allow
# +NaN+, +Infinity+, and +-Infinity+ in +source+;
# defaults to +false+.
#
# With the default:
#   source = '[NaN]'
#   # Raises JSON::ParserError (232: unexpected token at '[NaN]'):
#   a = JSON.parse(source)
#   source = '[Infinity]'
#   # Raises JSON::ParserError (232: unexpected token at '[Infinity]'):
#   a = JSON.parse(source)
#   source = '[-Infinity]'
#   # Raises JSON::ParserError (232: unexpected token at '[-Infinity]'):
#   a = JSON.parse(source)
# Allow:
#   source = '[NaN, Infinity, -Infinity]'
#   a = JSON.parse(source, {allow_nan: true})
#   a # => [NaN, Infinity, -Infinity]
# With a truthy value:
#   a = JSON.parse(source, {allow_nan: :foo})
#   a # => [NaN, Infinity, -Infinity]
#
# ---
#
# Option +symbolize_names+ specifies whether to use Symbols or Strings
# as keys in returned Hashes;
# defaults to +false+ (use Strings).
#
# With the default:
#   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
#   h = JSON.parse(source)
#   h # => {"a"=>"foo", "b"=>1.0, "c"=>true, "d"=>false, "e"=>nil}
# Use Symbols:
#   h = JSON.parse(source, {symbolize_names: true})
#   h # => {:a=>"foo", :b=>1.0, :c=>true, :d=>false, :e=>nil}
#
# ---
#
# Option +object_class+ specifies the Ruby class to be used
# for each \JSON object;
# defaults to \Hash.
#
# With the default:
#   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
#   h = JSON.parse(source)
#   h.class # => Hash
# Use class \OpenStruct:
#   o = JSON.parse(source, {object_class: OpenStruct})
#   o # => #<OpenStruct a="foo", b=1.0, c=true, d=false, e=nil>
# Try class \Object:
#   # Raises NoMethodError (undefined method `[]=' for #<Object:>):
#   JSON.parse(source, {object_class: Object})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Class)):
#   JSON.parse(source, {object_class: :foo})
#
# ---
#
# Option +array_class+ specifies the Ruby class to be used
# for each \JSON array;
# defaults to \Array.
#
# With the default:
#   source = '["foo", 1.0, true, false, null]'
#   a = JSON.parse(source)
#   a.class # => Array
# Use class \Set:
#   s = JSON.parse(source, {array_class: Set})
#   s # => #<Set: {"foo", 1.0, true, false, nil}>
# Try class \Object:
#   # Raises NoMethodError (undefined method `<<' for #<Object:>):
#   JSON.parse(source, {array_class: Object})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Class)):
#   JSON.parse(source, {array_class: :foo})
#
# ---
#
# Option +create_additions+
#
# === Generating \JSON
#
# You can parse a \String containing \JSON data using method
# - <tt>JSON.generate(source, opts)
# where
# - +source+ is a Ruby data structure.
# - +opts+ is a \Hash object containing options data.
#
# ---
#
# ==== Generating \JSON from a Ruby \Array:
#
# When +source+ is a Ruby \Array, JSON.generate returns a \JSON array:
#   source = ['foo', 1, 1.0, true, false, nil]
#
#
#
# Creating a JSON string for communication or serialization is
# just as simple.
#
# Option +indent+ specifies the string to be used for indentation.
# The default is the empty string <tt>''</tt>:
  #   source = '{"foo": {"bar": 1, "baz": 2}, "bat": [0, 1, 2]}'
#   h = JSON.parse(source)
#   h # => {"foo"=>{"bar"=>1, "baz"=>2}, "bat"=>[0, 1, 2]}
# With two spaces:
#   h = JSON.parse(source, {indent: '  '})
#   h # => {"foo"=>{"bar"=>1, "baz"=>2}, "bat"=>[0, 1, 2]}
#
# ---
#
# Option +create_additions+ specifies whether to
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#
# == \JSON Additions
#
# When you "round trip" a non-\String object from Ruby to \JSON and back,
# you have a new \String, instead of the object you began with:
#
#   range = Range.new(0, 2)
#   json = JSON.generate(range)
#   json # => "\"0..2\""
#   object = JSON.parse(json)
#   object # => "0..2"
#   object.class # => String
#
# You can use \JSON _additions_ to restore the original object.
# The addition is an extension of a ruby class, so that:
# - \JSON.generate stores more information in the \JSON string.
# - \JSON.parse, called with option +create_additions,
#   uses that information to create a proper Ruby object.
#
# This example generates \JSON from a \Range object,
# then parses that \JSON to form a (new) \Range object:
#   range = Range.new(0, 2)
#   require 'json/add/range'
#   json = JSON.generate(range)
#   json # => "{\"json_class\":\"Range\",\"a\":[0,2,false]}"
#   object = JSON.parse(json, create_additions: true)
#   object # => 0..2
#   object.class # => Range
#
# The \JSON module includes additions for certain classes.
# You can also craft custom additions (see below).
#
# === Built-in Additions
#
# The |JSON module includes additions for these classes:
# - BigDecimal
# - Complex
# - Date
# - DateTime
# - Exception
# - OpenStruct
# - Range
# - Rational
# - Regexp
# - Set
# - Struct
# - Symbol
# - Time
#
# To reduce punctuation clutter, the examples below
# show the generated \JSON via +puts+, rather than the usual +inspect+,
#
# ---
#
# \BigDecimal:
#   value = BigDecimal(0) # 0.0
# Without addition:
#   JSON.generate(value) # "0.0"
# With addition:
#   require 'json/add/bigdecimal'
#   JSON.generate(value) # {"json_class":"BigDecimal","b":"27:0.0"}
#
# ---
#
# \Complex:
#   value = Complex(1+0i) # (1+0i)
# Without addition:
#   JSON.generate(value) # "0.0"
# With addition:
#   require 'json/add/complex'
#   JSON.generate(value) # {"json_class":"Date","y":2020,"m":5,"d":1,"sg":2299161.0}
#
# ---
#
# \Date:
#   value = Date.today # #<Date: 2020-05-01 ((2458971j,0s,0n),+0s,2299161j)>
# Without addition:
#   JSON.generate(value) # "2020-05-01"
# With addition:
#   require 'json/add/date'
#   JSON.generate(value) # {"json_class":"Date","y":2020,"m":5,"d":1,"sg":2299161.0}
#
# ---
#
# \DateTime:
#   value = DateTime.now # 2020-05-01T11:00:47-05:00
# Without addition:
#   JSON.generate(value) # "2020-05-01T11:00:47-05:00"
# With addition:
#   require 'json/add/date_time'
#   JSON.generate(value) # {"json_class":"DateTime","y":2020,"m":5,"d":1,"H":11,"M":0,"S":47,"of":"-5/24","sg":2299161.0}
#
# ---
#
# \Exception (and its subclasses, including \RuntimeError):
#   value0 = Exception.new('A message') # #<Exception: A message>
#   value1 = RuntimeError.new('Another message') # #<RuntimeError: Another message>
# Without addition:
#   JSON.generate(value0) # "A message"
#   JSON.generate(value1) # "Another message"
# With addition:
#   require 'json/add/exception'
#   JSON.generate(value0) # {"json_class":"Exception","m":"A message","b":null}
#   JSON.generate(value1) # {"json_class":"RuntimeError","m":"Another message","b":null}
#
# ---
#
# \OpenStruct:
#   value = OpenStruct.new(name: 'Matz', language: 'Ruby') # #<OpenStruct name="Matz", language="Ruby">
# Without addition:
#   JSON.generate(value) # "#<OpenStruct name=\"Matz\", language=\"Ruby\">"
# With addition:
#   require 'json/add/ostruct'
#   JSON.generate(value) # {"json_class":"OpenStruct","t":{"name":"Matz","language":"Ruby"}}
#
# ---
#
# \Range:
#   value = Range.new(1, 3) # 1..3
# Without addition:
#   JSON.generate(value) # "1..3"
# With addition:
#   require 'json/add/range'
#   JSON.generate(value) # {"json_class":"Range","a":[1,3,false]}
#
# ---
#
# \Rational:
#   value = Rational.new(1, 3) # (1/3)
# Without addition:
#   JSON.generate(value) # "1/3"
# With addition:
#   require 'json/add/rational'
#   JSON.generate(value) # {"json_class":"Rational","n":1,"d":3}
#
# ---
#
# \Regexp:
#   value = Regexp.new('foo') # /foo/
# Without addition:
#   JSON.generate(value) # "(?-mix:foo)"
# With addition:
#   require 'json/add/regexp'
#   JSON.generate(value) # {"json_class":"Regexp","o":0,"s":"foo"}
#
# ---
#
# \Set:
#   value = Set.new([0, 1, 2]) # #<Set: {0, 1, 2}>
# Without addition:
#   JSON.generate(value) # "#<Set: {0, 1, 2}>"
# With addition:
#   require 'json/add/set'
#   JSON.generate(value) # {"json_class":"Set","a":[0,1,2]}
#
# ---
#
# \Struct:
#   value = Struct.new("Customer", :name, :address) # Struct::Customer
# Without addition:
#   JSON.generate(value) # "Struct::Customer"
# With addition:
#   require 'json/add/struct'
#   JSON.generate(value) # "Struct::Customer"
#
# ---
#
# \Symbol:
#   value = :foo # :foo
# Without addition:
#   JSON.generate(value) # :foo
# With addition:
#   require 'json/add/symbol'
#   JSON.generate(value) # {"json_class":"Symbol","s":"foo"}
#
# Custom Additions
#
module JSON
  require 'json/version'

  begin
    require 'json/ext'
  rescue LoadError
    require 'json/pure'
  end
end
