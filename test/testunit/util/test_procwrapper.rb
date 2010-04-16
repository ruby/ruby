# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require 'test/unit/util/procwrapper'

module Test
  module Unit
    module Util
      class TC_ProcWrapper < TestCase
        def munge_proc(&a_proc)
          return a_proc
        end
        def setup
          @original = proc {}
          @munged = munge_proc(&@original)
          @wrapped_original = ProcWrapper.new(@original)
          @wrapped_munged = ProcWrapper.new(@munged)
        end
        def test_wrapping
          assert_same(@original, @wrapped_original.to_proc, "The wrapper should return what was wrapped")
        end
        def test_hashing

          assert_equal(@wrapped_original.hash, @wrapped_munged.hash, "The original and munged should have the same hash when wrapped")
          assert_equal(@wrapped_original, @wrapped_munged, "The wrappers should be equivalent")

          a_hash = {@wrapped_original => @original}
          assert(a_hash[@wrapped_original], "Should be able to access the wrapper in the hash")
          assert_equal(a_hash[@wrapped_original], @original, "Should be able to access the wrapper in the hash")
        end
      end
    end
  end
end
