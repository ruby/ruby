require "test/unit"

require "csv"

class TestCSV < Test::Unit::TestCase
  module DifferentOFS
    def setup
      super
      @ofs, $, = $,, "-"
    end
    def teardown
      $, = @ofs
      super
    end
  end

  def self.with_diffrent_ofs
    Class.new(self).class_eval {include DifferentOFS}
  end
end
