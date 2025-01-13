# frozen_string_literal: true

require "test/unit"
require "core_assertions"

module MMTk
  class TestCase < ::Test::Unit::TestCase
    include Test::Unit::CoreAssertions

    def setup
      omit "Not running on MMTk" unless using_mmtk?
      super
    end

    private

    def using_mmtk?
      GC.config[:implementation] == "mmtk"
    end
  end
end
