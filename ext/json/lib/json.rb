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
# - \Array: an ordered list of values, enclosed by square brackets; example:
#
#     ["foo", 1, 1.0, 2.0e2, true, false, null]
#
# - \Object: a collection of name/value pairs, enclosed by curly braces;
#   each name is double-quoted text;
#   the values may be any \JSON values;
#   example:
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
# When the \JSON source is a scalar, JSON.parse returns a scalar:
#   s = JSON.parse('"foo"')
#   s # => "foo"
#   s.class # => String
#   n = JSON.parse('1')
#   n # => 1
#   n.class # => Integer
#   f = JSON.parse('1.0')
#   f # => 1.0
#   f.class # => Float
#   f = JSON.parse('2.0e2')
#   f # => 200
#   f.class # => Flaot
#   b = JSON.parse('true')
#   b # => true
#   b.class # => TrueClass
#   b = JSON.parse('false')
#   b # => false
#   b.class # => FalseClass
#   n = JSON.parse('null')
#   n # => nil
#   n.class # => NilClass
#
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
#   a = JSON.parse(source, {:max_nesting: 1})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Fixnum)):
#   JSON.parse(source, {:max_nesting => :foo})
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
#   a = JSON.parse(source, {:allow_nan: true})
#   a # => [NaN, Infinity, -Infinity]
# With a truthy value:
#   a = JSON.parse(source, {:allow_nan => :foo})
#   a # => [NaN, Infinity, -Infinity]
#
# ---
#
# Option +symbolize_names* specifies whether to use Symbols or Strings
# as keys in returned Hashes;
# defaults to +false+ (use Strings).
#
# With the default:
#   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
#   h = JSON.parse(source)
#   h # => {"a"=>"foo", "b"=>1.0, "c"=>true, "d"=>false, "e"=>nil}
# Use Symbols:
#   h = JSON.parse(source, {:symbolize_names: true})
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
#   o = JSON.parse(source, {:object_class: OpenStruct})
#   o # => #<OpenStruct a="foo", b=1.0, c=true, d=false, e=nil>
# Try class \Object:
#   # Raises NoMethodError (undefined method `[]=' for #<Object:>):
#   JSON.parse(source, {:object_class: Object})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Class)):
#   JSON.parse(source, {:object_class: :foo})
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
#   s = JSON.parse(source, {:array_class: Set})
#   s # => #<Set: {"foo", 1.0, true, false, nil}>
# Try class \Object:
#   # Raises NoMethodError (undefined method `<<' for #<Object:>):
#   JSON.parse(source, {:array_class: Object})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Class)):
#   JSON.parse(source, {:array_class: :foo})
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
#   h = JSON.parse(source, {:indent => ''})
#   h # => {"foo"=>{"bar"=>1, "baz"=>2}, "bat"=>[0, 1, 2]}
#
# ---
#
# Option +create_additions+ specifies whether to
#
# == Extended rendering and loading of Ruby objects
#
# JSON library provides optional _additions_ allowing to serialize and
# deserialize Ruby classes without loosing their type.
#
#   # without additions
#   require "json"
#   json = JSON.generate({range: 1..3, regex: /test/})
#   # => '{"range":"1..3","regex":"(?-mix:test)"}'
#   JSON.parse(json)
#   # => {"range"=>"1..3", "regex"=>"(?-mix:test)"}
#
#   # with additions
#   require "json/add/range"
#   require "json/add/regexp"
#   json = JSON.generate({range: 1..3, regex: /test/})
#   # => '{"range":{"json_class":"Range","a":[1,3,false]},"regex":{"json_class":"Regexp","o":0,"s":"test"}}'
#   JSON.parse(json)
#   # => {"range"=>{"json_class"=>"Range", "a"=>[1, 3, false]}, "regex"=>{"json_class"=>"Regexp", "o"=>0, "s"=>"test"}}
#   JSON.load(json)
#   # => {"range"=>1..3, "regex"=>/test/}
#
# See JSON.load for details.
module JSON
  require 'json/version'

  begin
    require 'json/ext'
  rescue LoadError
    require 'json/pure'
  end
end
