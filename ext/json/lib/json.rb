#frozen_string_literal: false
require 'json/common'

##
# = JavaScript Object Notation (JSON)
#
# JSON is a lightweight data-interchange format. It is easy for us
# humans to read and write. Plus, equally simple for machines to generate or parse.
# JSON is completely language agnostic, making it the ideal interchange format.
#
# Built on two universally available structures:
#
# 1. A collection of name/value pairs. Often referred to as an _object_, hash table,
#    record, struct, keyed list, or associative array.
# 2. An ordered list of values. More commonly called an _array_, vector, sequence or
#    list.
#
# To read more about JSON visit: http://json.org
#
# == Parsing JSON
#
# To parse a JSON string received by another application or generated within
# your existing application:
#
#   require 'json'
#
#   my_hash = JSON.parse('{"hello": "goodbye"}')
#   puts my_hash["hello"] # => "goodbye"
#
# Notice the extra quotes <tt>''</tt> around the hash notation. Ruby expects
# the argument to be a string and can't convert objects like a hash or array.
#
# Ruby converts your string into a hash
#
# == Generating JSON
#
# Creating a JSON string for communication or serialization is
# just as simple.
#
#   require 'json'
#
#   my_hash = {:hello => "goodbye"}
#   puts JSON.generate(my_hash) # => "{\"hello\":\"goodbye\"}"
#
# Or an alternative way:
#
#   require 'json'
#   puts {:hello => "goodbye"}.to_json # => "{\"hello\":\"goodbye\"}"
#
# <tt>JSON.generate</tt> only allows objects or arrays to be converted
# to JSON syntax. <tt>to_json</tt>, however, accepts many Ruby classes
# even though it acts only as a method for serialization:
#
#   require 'json'
#
#   1.to_json => "1"
#
# The {#generate}[rdoc-ref:JSON#generate] method accepts a variety of options
# to set the formatting of string output and defining what input is accepteable.
# There are also shortcut methods pretty_generate (with a set of options to
# generate human-readable multiline JSON) and fast_generate (with a set of
# options to generate JSON faster at the price of disabling some checks).
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
