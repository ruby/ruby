require 'test/unit'

module DidYouMean
  module TestHelper
    class << self
      attr_reader :root
    end

    if File.file?(File.expand_path('../lib/did_you_mean.rb', __dir__))
      # In this case we're being run from inside the gem, so we just want to
      # require the root of the library

      @root = File.expand_path('../lib/did_you_mean', __dir__)
      require_relative @root
    else
      # In this case we're being run from inside ruby core, and we want to
      # include the experimental features in the test suite

      @root = File.expand_path('../../lib/did_you_mean', __dir__)
      require_relative @root
      # We are excluding experimental features for now.
      # require_relative File.join(@root, 'experimental')
    end

    def assert_correction(expected, array)
      assert_equal Array(expected), array, "Expected #{array.inspect} to only include #{expected.inspect}"
    end
  end
end
