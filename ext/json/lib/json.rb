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
# This example shows a \Range being generated into \JSON
# and parsed back into Ruby, both without and with
# the addition for \Range:
#   range = Range.new(0, 2)
#   # This passage does not use the addition for Range.
#   json0 = JSON.generate(range)
#   ruby0 = JSON.parse(json0)
#   # This passage uses the addition for Range.
#   require 'json/add/range'
#   json1 = JSON.generate(range)
#   ruby1 = JSON.parse(json1, create_additions: true)
#   # Make a nice display.
#   display = <<EOT
#   Generated JSON:
#     Without addition:  #{json0} (#{json0.class})
#     With addition:     #{json1} (#{json1.class})
#   Parsed JSON:
#     Without addition:  #{ruby0.inspect} (#{ruby0.class})
#     With addition:     #{ruby1.inspect} (#{ruby1.class})
#   EOT
#   puts display
#
# This output shows the different results:
#   Generated JSON:
#     Without addition:  "0..2" (String)
#     With addition:     {"json_class":"Range","a":[0,2,false]} (String)
#   Parsed JSON:
#     Without addition:  "0..2" (String)
#     With addition:     0..2 (Range)
#
# The \JSON module includes additions for certain classes.
# You can also craft custom additions.  See {Custom \JSON Additions}[#module-label-Custom+JSON+Additions]
#
# === Built-in Additions
#
# <table><tr><td>Foo</td></tr></table>
#
# The \JSON module includes additions for these classes:
# - BigDecimal: <tt>require 'json/add/bigdecimal'</tt>
# - Complex: <tt>require 'json/add/complex'</tt>
# - Date: <tt>require 'json/add/date'</tt>
# - DateTime: <tt>require 'json/add/date_time'</tt>
# - Exception: <tt>require 'json/add/exception'</tt>
# - OpenStruct: <tt>require 'json/add/ostruct'</tt>
# - Range: <tt>require 'json/add/range'</tt>
# - Rational: <tt>require 'json/add/rational'</tt>
# - Regexp: <tt>require 'json/add/regexp'</tt>
# - Set: <tt>require 'json/add/set'</tt>
# - Struct: <tt>require 'json/add/struct'</tt>
# - Symbol: <tt>require 'json/add/symbol'</tt>
# - Time: <tt>require 'json/add/time'</tt>
#
# To reduce punctuation clutter, the examples below
# show the generated \JSON via +puts+, rather than the usual +inspect+,
#
# \BigDecimal:
#   require 'json/add/bigdecimal'
#   value = BigDecimal(0) # 0.0
#   json = JSON.generate(value) # {"json_class":"BigDecimal","b":"27:0.0"}
#   ruby = JSON.parse(json, create_additions: true) # 0.0
#
# \Complex:
#   require 'json/add/complex'
#   value = Complex(1+0i) # 1+0i
#   json = JSON.generate(value) # {"json_class":"Complex","r":1,"i":0}
#   ruby = JSON.parse(json, create_additions: true) # 1+0i
#   ruby.class # Complex
#
# \Date:
#   require 'json/add/date'
#   value = Date.today # 2020-05-02
#   json = JSON.generate(value) # {"json_class":"Date","y":2020,"m":5,"d":2,"sg":2299161.0}
#   ruby = JSON.parse(json, create_additions: true) # 2020-05-02
#   ruby.class # Date
#
# \DateTime:
#   require 'json/add/date_time'
#   value = DateTime.now # 2020-05-02T10:38:13-05:00
#   json = JSON.generate(value) # {"json_class":"DateTime","y":2020,"m":5,"d":2,"H":10,"M":38,"S":13,"of":"-5/24","sg":2299161.0}
#   ruby = JSON.parse(json, create_additions: true) # 2020-05-02T10:38:13-05:00
#   ruby.class # DateTime
#
# \Exception (and its subclasses including \RuntimeError):
#   require 'json/add/exception'
#   value = Exception.new('A message') # A message
#   json = JSON.generate(value) # {"json_class":"Exception","m":"A message","b":null}
#   ruby = JSON.parse(json, create_additions: true) # A message
#   ruby.class # Exception
#   value = RuntimeError.new('Another message') # Another message
#   json = JSON.generate(value) # {"json_class":"RuntimeError","m":"Another message","b":null}
#   ruby = JSON.parse(json, create_additions: true) # Another message
#   ruby.class # RuntimeError
#
# \OpenStruct:
#   require 'json/add/ostruct'
#   value = OpenStruct.new(name: 'Matz', language: 'Ruby') # #<OpenStruct name="Matz", language="Ruby">
#   json = JSON.generate(value) # {"json_class":"OpenStruct","t":{"name":"Matz","language":"Ruby"}}
#   ruby = JSON.parse(json, create_additions: true) # #<OpenStruct name="Matz", language="Ruby">
#   ruby.class # OpenStruct
#
# \Range:
#   require 'json/add/range'
#   value = Range.new(0, 2) # 0..2
#   json = JSON.generate(value) # {"json_class":"Range","a":[0,2,false]}
#   ruby = JSON.parse(json, create_additions: true) # 0..2
#   ruby.class # Range
#
# \Rational:
#   require 'json/add/rational'
#   value = Rational(1, 3) # 1/3
#   json = JSON.generate(value) # {"json_class":"Rational","n":1,"d":3}
#   ruby = JSON.parse(json, create_additions: true) # 1/3
#   ruby.class # Rational
#
# \Regexp:
#   require 'json/add/regexp'
#   value = Regexp.new('foo') # (?-mix:foo)
#   json = JSON.generate(value) # {"json_class":"Regexp","o":0,"s":"foo"}
#   ruby = JSON.parse(json, create_additions: true) # (?-mix:foo)
#   ruby.class # Regexp
#
# \Set:
#   require 'json/add/set'
#   value = Set.new([0, 1, 2]) # #<Set: {0, 1, 2}>
#   json = JSON.generate(value) # {"json_class":"Set","a":[0,1,2]}
#   ruby = JSON.parse(json, create_additions: true) # #<Set: {0, 1, 2}>
#   ruby.class # Set
#
# ---
#
# \Struct:
#   require 'json/add/struct'
#   Customer = Struct.new(:name, :address) # Customer
#   value = Customer.new("Dave", "123 Main") # #<struct Customer name="Dave", address="123 Main">
#   json = JSON.generate(value) # {"json_class":"Customer","v":["Dave","123 Main"]}
#   ruby = JSON.parse(json, create_additions: true) # #<struct Customer name="Dave", address="123 Main">
#   ruby.class # Customer
#
# \Symbol:
#   require 'json/add/symbol'
#   value = :foo # foo
#   json = JSON.generate(value) # {"json_class":"Symbol","s":"foo"}
#   ruby = JSON.parse(json, create_additions: true) # foo
#   ruby.class # Symbol
#
# \Time:
#   require 'json/add/time'
#   value = Time.now # 2020-05-02 11:28:26 -0500
#   json = JSON.generate(value) # {"json_class":"Time","s":1588436906,"n":840560000}
#   ruby = JSON.parse(json, create_additions: true) # 2020-05-02 11:28:26 -0500
#   ruby.class # Time
#
#
# === Custom \JSON Additions
#
# In addition to the \JSON additions provided,
# you can craft addition of your own,
# either for Ruby built-in classes or for classes of your own.
#
# Here's a user-defined class +Foo+:
#
#   class Foo
#     attr_accessor :bar, :baz
#     def initialize(bar, baz)
#       self.bar = bar
#       self.baz = baz
#     end
#   end
#
# Here's the \JSON addition for it:
#
#   # Extend class Foo with JSON addition.
#   class Foo
#     # Serialize Foo object with its class name and arguments
#     def to_json(*args)
#       {
#         JSON.create_id  => self.class.name,
#         'a'             => [ bar, baz ]
#       }.to_json(*args)
#     end
#     # Deserialize JSON string by constructing new Foo object with arguments.
#     def self.json_create(object)
#       new(*object['a'])
#     end
#   end
#
# Demonstration:
#   require 'json'
#   # This Foo object has no custom addition.
#   foo0 = Foo.new(0, 1)
#   json0 = JSON.generate(foo0)
#   obj0 = JSON.parse(json0)
#   # Lood the custom addition.
#   require_relative 'foo_addition'
#   # This foo has the custom addition.
#   foo1 = Foo.new(0, 1)
#   json1 = JSON.generate(foo1)
#   obj1 = JSON.parse(json1, create_additions: true)
#   #   Make a nice display.
#   display = <<EOT
#   Generated JSON:
#     Without custom addition:  #{json0} (#{json0.class})
#     With custom addition:     #{json1} (#{json1.class})
#   Parsed JSON:
#     Without custom addition:  #{obj0.inspect} (#{obj0.class})
#     With custom addition:     #{obj1.inspect} (#{obj1.class})
#   EOT
#   puts display
#
# Output:
#
#   Generated JSON:
#     Without custom addition:  "#<Foo:0x0000000006534e80>" (String)
#     With custom addition:     {"json_class":"Foo","a":[0,1]} (String)
#   Parsed JSON:
#     Without custom addition:  "#<Foo:0x0000000006534e80>" (String)
#     With custom addition:     #<Foo:0x0000000006473bb8 @bar=0, @baz=1> (Foo)
#
module JSON
  require 'json/version'

  begin
    require 'json/ext'
  rescue LoadError
    require 'json/pure'
  end
end
