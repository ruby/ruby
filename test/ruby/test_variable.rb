require 'test/unit'

$KCODE = 'none'

class TestVariable < Test::Unit::TestCase
  class Gods
    @@rule = "Uranus"
    def ruler0
      @@rule
    end

    def self.ruler1		# <= per method definition style
      @@rule
    end		   
    class << self			# <= multiple method definition style
      def ruler2
	@@rule
      end
    end
  end

  module Olympians
    @@rule ="Zeus"
    def ruler3
      @@rule
    end
  end

  class Titans < Gods
    @@rule = "Cronus"
    include Olympians           	# OK to cause warning (intentional)
  end

  def test_variable
    assert($$.instance_of?(Fixnum))
    
    # read-only variable
    begin
      $$ = 5
      assert false
    rescue NameError
      assert true
    end
    
    foobar = "foobar"
    $_ = foobar
    assert($_ == foobar)

    assert(Gods.new.ruler0 == "Cronus")
    assert(Gods.ruler1 == "Cronus")
    assert(Gods.ruler2 == "Cronus")
    assert(Titans.ruler1 == "Cronus")
    assert(Titans.ruler2 == "Cronus")
    atlas = Titans.new
    assert(atlas.ruler0 == "Cronus")
    assert(atlas.ruler3 == "Zeus")
  end
end
