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
          tests = []
          @source.each_object(Class) do |klass|
            tests.concat(klass.suite.tests) if(Test::Unit::TestCase > klass)
          end
          tests.sort_by{|t| t.name}.each{|test| suite << test if(include(test))}
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
