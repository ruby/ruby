# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/collector'

module Test
  module Unit
    module Collector
      class ObjectSpace
        include Test::Unit::Collector
        
        NAME = 'collected from the subclasses of TestCase'
        
        def initialize(source=nil)
          super()
          @source = source
        end
        
        def collect(name=NAME)
          suite = TestSuite.new(name)
          sub_suites = []
          if @source
            @source.each_object(Class) do |klass|
              if(Test::Unit::TestCase > klass)
                add_suite(sub_suites, klass.suite)
              end
            end
          else
            TestCase::DECENDANT_CLASSES.each do |klass|
              add_suite(sub_suites, klass.suite)
            end
          end
          sort(sub_suites).each{|s| suite << s}
          suite
        end
      end
    end
  end
end
