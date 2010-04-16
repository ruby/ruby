module Test
  module Unit
    module Util
      module BacktraceFilter
        TESTUNIT_FILE_SEPARATORS = %r{[\\/:]}
        TESTUNIT_PREFIX = __FILE__.split(TESTUNIT_FILE_SEPARATORS)[0..-3]
        TESTUNIT_RB_FILE = /\.rb\Z/

        def filter_backtrace(backtrace, prefix=nil)
          return ["No backtrace"] unless(backtrace)
          split_p = if(prefix)
            prefix.split(TESTUNIT_FILE_SEPARATORS)
          else
            TESTUNIT_PREFIX
          end
          match = proc do |e|
            split_e = e.split(TESTUNIT_FILE_SEPARATORS)[0, split_p.size]
            next false unless(split_e[0..-2] == split_p[0..-2])
            split_e[-1].sub(TESTUNIT_RB_FILE, '') == split_p[-1]
          end
          return backtrace unless(backtrace.detect(&match))
          found_prefix = false
          new_backtrace = backtrace.reverse.reject do |e|
            if(match[e])
              found_prefix = true
              true
            elsif(found_prefix)
              false
            else
              true
            end
          end.reverse
          new_backtrace = (new_backtrace.empty? ? backtrace : new_backtrace)
          new_backtrace = new_backtrace.reject(&match)
          new_backtrace.empty? ? backtrace : new_backtrace
        end
      end
    end
  end
end
