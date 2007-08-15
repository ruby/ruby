module Test
  module Unit
    module Collector
      def initialize
        @filters = []
      end

      def filter=(filters)
        @filters = case(filters)
          when Proc
            [filters]
          when Array
            filters
        end
      end

      def add_suite(destination, suite)
        to_delete = suite.tests.find_all{|t| !include?(t)}
        to_delete.each{|t| suite.delete(t)}
        destination << suite unless(suite.size == 0)
      end

      def include?(test)
        return true if(@filters.empty?)
        @filters.each do |filter|
          result = filter[test]
          if(result.nil?)
            next
          elsif(!result)
            return false
          else
            return true
          end
        end
        true
      end

      def sort(suites)
        suites.sort_by{|s| s.name}
      end
    end
  end
end
