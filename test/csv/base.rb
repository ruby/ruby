require "test/unit"

require "csv"

require_relative "../with_diffent_ofs.rb"

class TestCSV < Test::Unit::TestCase
  include DifferentOFS
end
