# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/collector/objectspace'

module Test
  module Unit
    module Collector
      class TC_ObjectSpace < TestCase
        def setup
          @tc1 = Class.new(TestCase) do
            def test_1
            end
            def test_2
            end
          end

          @tc2 = Class.new(TestCase) do
            def test_0
            end
          end

          @no_tc = Class.new do
            def test_4
            end
          end
 
          @object_space = {Class => [@tc1, @tc2, @no_tc], String => ['']}
          def @object_space.each_object(type)
            self[type].each{|item| yield(item) }
          end
        end
        
        def test_basic_collection
          expected = TestSuite.new("name")
          expected << @tc2.new('test_0')
          expected << @tc1.new('test_1')
          expected << @tc1.new('test_2')
          assert_equal(expected, ObjectSpace.new(@object_space).collect("name"))
        end
        
        def test_filtered_collection
          expected = TestSuite.new(ObjectSpace::NAME)
          collector = ObjectSpace.new(@object_space)
          collector.filter = proc{|test| false}
          assert_equal(expected, collector.collect)

          expected = TestSuite.new(ObjectSpace::NAME)
          expected << @tc2.new('test_0')
          expected << @tc1.new('test_1')
          expected << @tc1.new('test_2')
          collector = ObjectSpace.new(@object_space)
          collector.filter = proc{|test| true}
          assert_equal(expected, collector.collect)

          expected = TestSuite.new(ObjectSpace::NAME)
          expected << @tc2.new('test_0')
          expected << @tc1.new('test_1')
          collector = ObjectSpace.new(@object_space)
          collector.filter = proc{|test| ['test_1', 'test_0'].include?(test.method_name)}
          assert_equal(expected, collector.collect)

          expected = TestSuite.new(ObjectSpace::NAME)
          expected << @tc2.new('test_0')
          expected << @tc1.new('test_1')
          collector = ObjectSpace.new(@object_space)
          collector.filter = [proc{|test| test.method_name == 'test_1'}, proc{|test| test.method_name == 'test_0'}]
          assert_equal(expected, collector.collect)
        end
      end
    end
  end
end
