require 'test/unit'

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
    assert_instance_of(Fixnum, $$)
    
    # read-only variable
    assert_raises(NameError) do
      $$ = 5
    end

    foobar = "foobar"
    $_ = foobar
    assert_equal(foobar, $_)

    assert_equal("Cronus", Gods.new.ruler0)
    assert_equal("Cronus", Gods.ruler1)
    assert_equal("Cronus", Gods.ruler2)
    assert_equal("Cronus", Titans.ruler1)
    assert_equal("Cronus", Titans.ruler2)
    atlas = Titans.new
    assert_equal("Cronus", atlas.ruler0)
    assert_equal("Zeus", atlas.ruler3)
  end
end
