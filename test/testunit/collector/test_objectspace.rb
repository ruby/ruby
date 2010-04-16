# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require 'test/unit/collector/objectspace'

module Test
  module Unit
    module Collector
      class TC_ObjectSpace < TestCase
        def setup
          @tc1 = Class.new(TestCase) do
            def self.name
              "tc_1"
            end
            def test_1
            end
            def test_2
            end
          end

          @tc2 = Class.new(TestCase) do
            def self.name
              "tc_2"
            end
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

          @c = ObjectSpace.new(@object_space)
        end

        def full_suite(name=ObjectSpace::NAME)
          expected = TestSuite.new(name)
          expected << (TestSuite.new(@tc1.name) << @tc1.new('test_1') << @tc1.new('test_2'))
          expected << (TestSuite.new(@tc2.name) << @tc2.new('test_0'))
        end

        def empty_suite
          TestSuite.new(ObjectSpace::NAME)
        end

        def test_basic_collection
          assert_equal(full_suite("name"), @c.collect("name"))

          @c.filter = []
          assert_equal(full_suite("name"), @c.collect("name"))
        end

        def test_filtered_collection
          @c.filter = proc{false}
          assert_equal(empty_suite, @c.collect)

          @c.filter = proc{true}
          assert_equal(full_suite, @c.collect)

          @c.filter = proc{nil}
          assert_equal(full_suite, @c.collect)

          @c.filter = [proc{false}, proc{true}]
          assert_equal(empty_suite, @c.collect)

          @c.filter = [proc{true}, proc{false}]
          assert_equal(full_suite, @c.collect)

          @c.filter = [proc{nil}, proc{false}]
          assert_equal(empty_suite, @c.collect)

          @c.filter = [proc{nil}, proc{true}]
          assert_equal(full_suite, @c.collect)

          expected = TestSuite.new(ObjectSpace::NAME)
          expected << (TestSuite.new(@tc1.name) << @tc1.new('test_1'))
          expected << (TestSuite.new(@tc2.name) << @tc2.new('test_0'))
          @c.filter = proc{|test| ['test_1', 'test_0'].include?(test.method_name)}
          assert_equal(expected, @c.collect)

          expected = TestSuite.new(ObjectSpace::NAME)
          expected << (TestSuite.new(@tc1.name) << @tc1.new('test_1'))
          expected << (TestSuite.new(@tc2.name) << @tc2.new('test_0'))
          @c.filter = [proc{|t| t.method_name == 'test_1' ? true : nil}, proc{|t| t.method_name == 'test_0' ? true : nil}, proc{false}]
          assert_equal(expected, @c.collect)
        end
      end
    end
  end
end
