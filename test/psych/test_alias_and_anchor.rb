require 'psych/helper'

class ObjectWithInstanceVariables
  attr_accessor :var1, :var2
end

class SubStringWithInstanceVariables < String
  attr_accessor :var1
end

module Psych
 class TestAliasAndAnchor < TestCase
   def test_mri_compatibility
     yaml = <<EOYAML
---
- &id001 !ruby/object {}

- *id001
- *id001
EOYAML
     result = Psych.load yaml
     result.each {|el| assert_same(result[0], el) }
   end

   def test_mri_compatibility_object_with_ivars
  yaml = <<EOYAML
--- 
- &id001 !ruby/object:ObjectWithInstanceVariables 
  var1: test1
  var2: test2
- *id001
- *id001
EOYAML

     result = Psych.load yaml
     result.each do |el| 
      assert_same(result[0], el)
      assert_equal('test1', el.var1)
      assert_equal('test2', el.var2)
    end
   end

   def test_mri_compatibility_substring_with_ivars
    yaml = <<EOYAML
--- 
- &id001 !str:SubStringWithInstanceVariables 
  str: test
  "@var1": test
- *id001
- *id001
EOYAML
     result = Psych.load yaml
     result.each do |el|
      assert_same(result[0], el)
      assert_equal('test', el.var1)
    end
   end

   def test_anchor_alias_round_trip
     o = Object.new
     original = [o,o,o]

     yaml = Psych.dump original
     result = Psych.load yaml
     result.each {|el| assert_same(result[0], el) }
   end

   def test_anchor_alias_round_trip_object_with_ivars
     o = ObjectWithInstanceVariables.new
     o.var1 = 'test1'
     o.var2 = 'test2'
     original = [o,o,o]

     yaml = Psych.dump original
     result = Psych.load yaml
     result.each do |el|
      assert_same(result[0], el)
      assert_equal('test1', el.var1)
      assert_equal('test2', el.var2)
    end
   end

   def test_anchor_alias_round_trip_substring_with_ivars
     o = SubStringWithInstanceVariables.new
     o.var1 = 'test'
     original = [o,o,o]

     yaml = Psych.dump original
     result = Psych.load yaml
     result.each do |el|
      assert_same(result[0], el)
      assert_equal('test', el.var1)
    end
   end
 end
end
