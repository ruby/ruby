# frozen_string_literal: true

module MMTk
  class TestCase < ::Test::Unit::TestCase
    def setup
      omit "Not running on MMTk" unless using_mmtk?
      super
    end

    private

    def using_mmtk?
      GC.config(:implementation) == "mmtk"
    end
  end
end
