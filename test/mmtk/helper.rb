# frozen_string_literal: true

require "test/unit"
require "core_assertions"

module MMTk
  class TestCase < ::Test::Unit::TestCase
    include Test::Unit::CoreAssertions

    def setup
      omit "Not running on MMTk" unless using_mmtk?

      @original_timeout_scale = EnvUtil.timeout_scale
      timeout_scale = ENV["RUBY_TEST_TIMEOUT_SCALE"].to_f
      EnvUtil.timeout_scale = timeout_scale if timeout_scale > 0

      super
    end

    def teardown
      if using_mmtk?
        EnvUtil.timeout_scale = @original_timeout_scale
      end
    end

    private

    def using_mmtk?
      GC.config[:implementation] == "mmtk"
    end
  end
end
