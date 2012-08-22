require 'psych/helper'
require 'yaml'

module Psych
 class TestEngineManager < TestCase
   def test_bad_engine
     assert_raises(ArgumentError) do
       YAML::ENGINE.yamler = 'foooo'
     end
   end

   def test_set_psych
     YAML::ENGINE.yamler = 'psych'
     assert_equal Psych, YAML
     assert_equal 'psych', YAML::ENGINE.yamler
   end

   A = Struct.new(:name)

   def test_dump_types
     YAML::ENGINE.yamler = 'psych'

     assert_to_yaml ::Object.new
     assert_to_yaml Time.now
     assert_to_yaml Date.today
     assert_to_yaml('a' => 'b')
     assert_to_yaml A.new('foo')
     assert_to_yaml %w{a b}
     assert_to_yaml Exception.new('foo')
     assert_to_yaml "hello!"
     assert_to_yaml :fooo
     assert_to_yaml(1..10)
     assert_to_yaml(/hello!~/)
     assert_to_yaml 1
     assert_to_yaml 1.2
     assert_to_yaml Rational(1, 2)
     assert_to_yaml Complex(1, 2)
     assert_to_yaml true
     assert_to_yaml false
     assert_to_yaml nil
   end

   def assert_to_yaml obj
     assert obj.to_yaml, "#{obj.class} to_yaml works"
   end
 end
end
