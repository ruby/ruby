# frozen_string_literal: true
require 'json/common'

##
# = JavaScript \Object Notation (\JSON)
#
# \JSON is a lightweight data-interchange format.
#
# \JSON is easy for us humans to read and write,
# and equally simple for machines to read (parse) and write (generate).
#
# \JSON is language-independent, making it an ideal interchange format
# for applications in differing programming languages
# and on differing operating systems.
#
# == \JSON Values
#
# A \JSON value is one of the following:
# - Double-quoted text:  <tt>"foo"</tt>.
# - Number:  +1+, +1.0+, +2.0e2+.
# - Boolean:  +true+, +false+.
# - Null: +null+.
# - \Array: an ordered list of values, enclosed by square brackets:
#     ["foo", 1, 1.0, 2.0e2, true, false, null]
#
# - \Object: a collection of name/value pairs, enclosed by curly braces;
#   each name is double-quoted text;
#   the values may be any \JSON values:
#     {"a": "foo", "b": 1, "c": 1.0, "d": 2.0e2, "e": true, "f": false, "g": null}
#
# A \JSON array or object may contain nested arrays, objects, and scalars
# to any depth:
#   {"foo": {"bar": 1, "baz": 2}, "bat": [0, 1, 2]}
#   [{"foo": 0, "bar": 1}, ["baz", 2]]
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
# either of two methods:
# - <tt>JSON.parse(source, opts)</tt>
# - <tt>JSON.parse!(source, opts)</tt>
#
# where
# - +source+ is a Ruby object.
# - +opts+ is a \Hash object containing options
#   that control both input allowed and output formatting.
#
# The difference between the two methods
# is that JSON.parse! omits some checks
# and may not be safe for some +source+ data;
# use it only for data from trusted sources.
# Use the safer method JSON.parse for less trusted sources.
#
# ==== Parsing \JSON Arrays
#
# When +source+ is a \JSON array, JSON.parse by default returns a Ruby \Array:
#   json = '["foo", 1, 1.0, 2.0e2, true, false, null]'
#   ruby = JSON.parse(json)
#   ruby # => ["foo", 1, 1.0, 200.0, true, false, nil]
#   ruby.class # => Array
#
# The \JSON array may contain nested arrays, objects, and scalars
# to any depth:
#   json = '[{"foo": 0, "bar": 1}, ["baz", 2]]'
#   JSON.parse(json) # => [{"foo"=>0, "bar"=>1}, ["baz", 2]]
#
# ==== Parsing \JSON \Objects
#
# When the source is a \JSON object, JSON.parse by default returns a Ruby \Hash:
#   json = '{"a": "foo", "b": 1, "c": 1.0, "d": 2.0e2, "e": true, "f": false, "g": null}'
#   ruby = JSON.parse(json)
#   ruby # => {"a"=>"foo", "b"=>1, "c"=>1.0, "d"=>200.0, "e"=>true, "f"=>false, "g"=>nil}
#   ruby.class # => Hash
#
# The \JSON object may contain nested arrays, objects, and scalars
# to any depth:
#   json = '{"foo": {"bar": 1, "baz": 2}, "bat": [0, 1, 2]}'
#   JSON.parse(json) # => {"foo"=>{"bar"=>1, "baz"=>2}, "bat"=>[0, 1, 2]}
#
# ==== Parsing \JSON Scalars
#
# When the source is a \JSON scalar (not an array or object),
# JSON.parse returns a Ruby scalar.
#
# \String:
#   ruby = JSON.parse('"foo"')
#   ruby # => 'foo'
#   ruby.class # => String
# \Integer:
#   ruby = JSON.parse('1')
#   ruby # => 1
#   ruby.class # => Integer
# \Float:
#   ruby = JSON.parse('1.0')
#   ruby # => 1.0
#   ruby.class # => Float
#   ruby = JSON.parse('2.0e2')
#   ruby # => 200
#   ruby.class # => Float
# Boolean:
#   ruby = JSON.parse('true')
#   ruby # => true
#   ruby.class # => TrueClass
#   ruby = JSON.parse('false')
#   ruby # => false
#   ruby.class # => FalseClass
# Null:
#   ruby = JSON.parse('null')
#   ruby # => nil
#   ruby.class # => NilClass
#
# ==== Parsing Options
#
# ====== Input Options
#
# Option +max_nesting+ (\Integer) specifies the maximum nesting depth allowed;
# defaults to +100+;
# You can set it to +false+ to disable depth checking entirely, but that is dangerous
# when parsing untrusted input.
#
# With the default, +100+:
#   source = '[0, [1, [2, [3]]]]'
#   ruby = JSON.parse(source)
#   ruby # => [0, [1, [2, [3]]]]
# Too deep:
#   # Raises JSON::NestingError (nesting of 2 is too deep):
#   JSON.parse(source, {max_nesting: 1})
# Bad value:
#   # Raises TypeError (wrong argument type Symbol (expected Fixnum)):
#   JSON.parse(source, {max_nesting: :foo})
#
# ---
#
# Option +allow_duplicate_key+ specifies whether duplicate keys in objects
# should be ignored or cause an error to be raised:
#
# When set to +false+, the default:
#   JSON.parse('{"a": 1, "a":2}') => duplicate key at line 1 column 1 (JSON::ParserError)
#
# When set to +true+:
#   # The last value is used.
#   JSON.parse('{"a": 1, "a":2}', allow_duplicate_key: true) => {"a" => 2}
#
# ---
#
# Option +allow_nan+ (boolean) specifies whether to allow
# NaN, Infinity, and MinusInfinity in +source+;
# defaults to +false+.
#
# With the default, +false+:
#   # Raises JSON::ParserError (225: unexpected token at '[NaN]'):
#   JSON.parse('[NaN]')
#   # Raises JSON::ParserError (232: unexpected token at '[Infinity]'):
#   JSON.parse('[Infinity]')
#   # Raises JSON::ParserError (248: unexpected token at '[-Infinity]'):
#   JSON.parse('[-Infinity]')
# Allow:
#   source = '[NaN, Infinity, -Infinity]'
#   ruby = JSON.parse(source, {allow_nan: true})
#   ruby # => [NaN, Infinity, -Infinity]
#
# ---
#
# Option +allow_trailing_comma+ (boolean) specifies whether to allow
# trailing commas in objects and arrays;
# defaults to +false+.
#
# With the default, +false+:
#   JSON.parse('[1,]') # unexpected character: ']' at line 1 column 4 (JSON::ParserError)
#
# When enabled:
#   JSON.parse('[1,]', allow_trailing_comma: true) # => [1]
#
# ---
#
# Option +allow_comments+ (boolean) specifies whether to allow
# JavaScript style comments (either <tt>// comment</tt> or <tt>/* comment */</tt>);
# defaults to +false+.
#
# When set to +false+, the default:
#   JSON.parse('/* comment */ {"a": 1, "a":2}') # unexpected character: '/' at line 1 column 1 (JSON::ParserError)
#
# When set to +true+, comments are ignored:
#   JSON.parse('/* comment */ {"a": 1, "a":2} // more comment') # => {"a" => 2}
#
# ---
#
# Option +allow_control_characters+ (boolean) specifies whether to allow
# unescaped ASCII control characters, such as newlines, in strings;
# defaults to +false+.
#
# With the default, +false+:
#   JSON.parse(%{"Hello\nWorld"}) # invalid ASCII control character in string (JSON::ParserError)
#
# When enabled:
#   JSON.parse(%{"Hello\nWorld"}, allow_control_characters: true) # => "Hello\nWorld"
#
# ---
#
# Option +allow_invalid_escape+ (boolean) specifies whether to ignore backslahes that are followed
# by an invalid escape character in strings;
# defaults to +false+.
#
# With the default, +false+:
#   JSON.parse('"Hell\o"') # invalid escape character in string (JSON::ParserError)
#
# When enabled:
#   JSON.parse('"Hell\o"', allow_invalid_escape: true) # => "Hello"
#
# ====== Output Options
#
# Option +freeze+ (boolean) specifies whether the returned objects will be frozen;
# defaults to +false+.
#
# Option +symbolize_names+ (boolean) specifies whether returned \Hash keys
# should be Symbols;
# defaults to +false+ (use Strings).
#
# With the default, +false+:
#   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
#   ruby = JSON.parse(source)
#   ruby # => {"a"=>"foo", "b"=>1.0, "c"=>true, "d"=>false, "e"=>nil}
# Use Symbols:
#   ruby = JSON.parse(source, {symbolize_names: true})
#   ruby # => {:a=>"foo", :b=>1.0, :c=>true, :d=>false, :e=>nil}
#
# ---
#
# Option +object_class+ (\Class) specifies the Ruby class to be used
# for each \JSON object;
# defaults to \Hash.
#
# With the default, \Hash:
#   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
#   ruby = JSON.parse(source)
#   ruby.class # => Hash
# Use class \OpenStruct:
#   ruby = JSON.parse(source, {object_class: OpenStruct})
#   ruby # => #<OpenStruct a="foo", b=1.0, c=true, d=false, e=nil>
#
# ---
#
# Option +array_class+ (\Class) specifies the Ruby class to be used
# for each \JSON array;
# defaults to \Array.
#
# With the default, \Array:
#   source = '["foo", 1.0, true, false, null]'
#   ruby = JSON.parse(source)
#   ruby.class # => Array
# Use class \Set:
#   ruby = JSON.parse(source, {array_class: Set})
#   ruby # => #<Set: {"foo", 1.0, true, false, nil}>
#
# === Generating \JSON
#
# To generate a Ruby \String containing \JSON data,
# use method <tt>JSON.generate(source, opts)</tt>, where
# - +source+ is a Ruby object.
# - +opts+ is a \Hash object containing options
#   that control both input allowed and output formatting.
#
# ==== Generating \JSON from Arrays
#
# When the source is a Ruby \Array, JSON.generate returns
# a \String containing a \JSON array:
#   ruby = [0, 's', :foo]
#   json = JSON.generate(ruby)
#   json # => '[0,"s","foo"]'
#
# The Ruby \Array array may contain nested arrays, hashes, and scalars
# to any depth:
#   ruby = [0, [1, 2], {foo: 3, bar: 4}]
#   json = JSON.generate(ruby)
#   json # => '[0,[1,2],{"foo":3,"bar":4}]'
#
# ==== Generating \JSON from Hashes
#
# When the source is a Ruby \Hash, JSON.generate returns
# a \String containing a \JSON object:
#   ruby = {foo: 0, bar: 's', baz: :bat}
#   json = JSON.generate(ruby)
#   json # => '{"foo":0,"bar":"s","baz":"bat"}'
#
# The Ruby \Hash array may contain nested arrays, hashes, and scalars
# to any depth:
#   ruby = {foo: [0, 1], bar: {baz: 2, bat: 3}, bam: :bad}
#   json = JSON.generate(ruby)
#   json # => '{"foo":[0,1],"bar":{"baz":2,"bat":3},"bam":"bad"}'
#
# ==== Generating \JSON from Other Objects
#
# When the source is neither an \Array nor a \Hash,
# the generated \JSON data depends on the class of the source.
#
# When the source is a Ruby \Integer or \Float, JSON.generate returns
# a \String containing a \JSON number:
#   JSON.generate(42) # => '42'
#   JSON.generate(0.42) # => '0.42'
#
# When the source is a Ruby \String, JSON.generate returns
# a \String containing a \JSON string (with double-quotes):
#   JSON.generate('A string') # => '"A string"'
#
# When the source is +true+, +false+ or +nil+, JSON.generate returns
# a \String containing the corresponding \JSON token:
#   JSON.generate(true) # => 'true'
#   JSON.generate(false) # => 'false'
#   JSON.generate(nil) # => 'null'
#
# When the source is none of the above, JSON.generate returns
# a \String containing a \JSON string representation of the source:
#   JSON.generate(:foo) # => '"foo"'
#   JSON.generate(Complex(0, 0)) # => '"0+0i"'
#   JSON.generate(Dir.new('.')) # => '"#<Dir>"'
#
# ==== Generating Options
#
# ====== Input Options
#
# Option +allow_nan+ (boolean) specifies whether
# +NaN+, +Infinity+, and <tt>-Infinity</tt> may be generated;
# defaults to +false+.
#
# With the default, +false+:
#   # Raises JSON::GeneratorError (920: NaN not allowed in JSON):
#   JSON.generate(JSON::NaN)
#   # Raises JSON::GeneratorError (917: Infinity not allowed in JSON):
#   JSON.generate(JSON::Infinity)
#   # Raises JSON::GeneratorError (917: -Infinity not allowed in JSON):
#   JSON.generate(JSON::MinusInfinity)
#
# Allow:
#   ruby = [Float::NAN, Float::INFINITY, JSON::NaN, JSON::Infinity, JSON::MinusInfinity]
#   JSON.generate(ruby, allow_nan: true) # => '[NaN,Infinity,NaN,Infinity,-Infinity]'
#
# ---
#
# Option +allow_duplicate_key+ (boolean) specifies whether
# hashes with duplicate keys should be allowed or produce an error.
# defaults to emit a deprecation warning.
#
# With the default, <tt>false</tt>:
#   JSON.generate({ foo: 1, "foo" => 2 })
#   # detected duplicate key "foo" in {foo: 1, "foo" => 2} (JSON::GeneratorError)
#
# With <tt>true</tt>
#   JSON.generate({ foo: 1, "foo" => 2 }, allow_duplicate_key: true)
#   # => '{"foo":1,"foo":2}'
#
# ---
#
# Option +max_nesting+ (\Integer) specifies the maximum nesting depth
# in +obj+; defaults to +100+.
#
# With the default, +100+:
#   obj = [[[[[[0]]]]]]
#   JSON.generate(obj) # => '[[[[[[0]]]]]]'
#
# Too deep:
#   # Raises JSON::NestingError (nesting of 2 is too deep):
#   JSON.generate(obj, max_nesting: 2)
#
# With +false+:
#   obj = []
#   obj[0] = obj
#   # Raises  SystemStackError: stack level too deep
#   JSON.generate(obj, max_nesting: false)
#
# Setting +max_nesting+ to +false+ or a very large number can lead to a stack overflow
# which may leave the process in an unrecoverable state.
# It is highly discouraged.
#
# ====== Escaping Options
#
# Options +script_safe+ (boolean) specifies wether <tt>'\u2028'</tt>, <tt>'\u2029'</tt>
# and <tt>'/'</tt> should be escaped as to make the JSON object safe to interpolate in script
# tags.
#
# Options +ascii_only+ (boolean) specifies wether all characters outside the ASCII range
# should be escaped.
#
# ====== Output Options
#
# The default formatting options generate the most compact
# \JSON data, all on one line and with no whitespace.
#
# You can use these formatting options to generate
# \JSON data in a more open format, using whitespace.
# See also JSON.pretty_generate.
#
# - Option +array_nl+ (\String) specifies a string (usually a newline)
#   to be inserted after each \JSON array; defaults to the empty \String, <tt>''</tt>.
# - Option +object_nl+ (\String) specifies a string (usually a newline)
#   to be inserted after each \JSON object; defaults to the empty \String, <tt>''</tt>.
# - Option +indent+ (\String) specifies the string (usually spaces) to be
#   used for indentation; defaults to the empty \String, <tt>''</tt>;
#   has no effect unless options +array_nl+ or +object_nl+ specify newlines.
# - Option +space+ (\String) specifies a string (usually a space) to be
#   inserted after the colon in each \JSON object's pair;
#   defaults to the empty \String, <tt>''</tt>.
# - Option +space_before+ (\String) specifies a string (usually a space) to be
#   inserted before the colon in each \JSON object's pair;
#   defaults to the empty \String, <tt>''</tt>.
# - Option +sort_keys+ (boolean or \Proc) controls whether and how the keys of a
#   hash are sorted when generating the output; defaults to <tt>false</tt>.
#   When +true+, keys are sorted lexicographically. When a \Proc, it receives
#   the entire \Hash and must return a \Hash with its pairs in the desired
#   order, allowing for arbitrary sort orders.
#
# In this example, +obj+ is used first to generate the shortest
# \JSON data (no whitespace), then again with all formatting options
# specified:
#
#   obj = {foo: [:bar, :baz], bat: {bam: 0, bad: 1}}
#   json = JSON.generate(obj)
#   puts 'Compact:', json
#   opts = {
#     array_nl: "\n",
#     object_nl: "\n",
#     indent: '  ',
#     space_before: ' ',
#     space: ' '
#   }
#   puts 'Open:', JSON.generate(obj, opts)
#
# Output:
#   Compact:
#   {"foo":["bar","baz"],"bat":{"bam":0,"bad":1}}
#   Open:
#   {
#     "foo" : [
#       "bar",
#       "baz"
#   ],
#     "bat" : {
#       "bam" : 0,
#       "bad" : 1
#     }
#   }
#
module JSON
  require 'json/version'
  require 'json/ext'
end
