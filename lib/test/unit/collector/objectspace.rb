# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit
    module Collector
      class ObjectSpace
        NAME = 'collected from the ObjectSpace'
        
        def initialize(source=::ObjectSpace)
          @source = source
          @filters = []
        end
        
        def collect(name=NAME)
          suite = TestSuite.new(name)
          sub_suites = []
          @source.each_object(Class) do |klass|
            if(Test::Unit::TestCase > klass)
              sub_suite = klass.suite
              to_delete = sub_suite.tests.find_all{|t| !include(t)}
              to_delete.each{|t| sub_suite.delete(t)}
              sub_suites << sub_suite unless(sub_suite.size == 0)
            end
          end
          sub_suites.sort_by{|s| s.name}.each{|s| suite << s}
          suite
        end
        
        def include(test)
          return true if(@filters.empty?)
          @filters.each do |filter|
            return true if(filter.call(test))
          end
          false
        end
        
        def filter=(filters)
          @filters = case(filters)
            when Proc
              [filters]
            when Array
              filters
          end
        end
      end
    end
  end
end
