# frozen_string_literal: false
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
    @@rule = "Cronus"			# modifies @@rule in Gods
    include Olympians
    def ruler4
      EnvUtil.suppress_warning {
        @@rule
      }
    end
  end

  def test_variable
    assert_instance_of(Integer, $$)

    # read-only variable
    assert_raise(NameError) do
      $$ = 5
    end
    assert_normal_exit("$*=0; $*", "[ruby-dev:36698]")

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
    assert_equal("Cronus", atlas.ruler4)
    assert_nothing_raised do
      class << Gods
        defined?(@@rule) && @@rule
      end
    end
  end

  def test_local_variables
    lvar = 1
    assert_instance_of(Symbol, local_variables[0], "[ruby-dev:34008]")
    lvar
  end

  def test_local_variables2
    x = 1
    proc do |y|
      assert_equal([:x, :y], local_variables.sort)
    end.call
    x
  end

  def test_local_variables3
    x = 1
    proc do |y|
      1.times do |z|
        assert_equal([:x, :y, :z], local_variables.sort)
      end
    end.call
    x
  end

  def test_shadowing_local_variables
    bug9486 = '[ruby-core:60501] [Bug #9486]'
    assert_equal([:x, :bug9486], tap {|x| break local_variables}, bug9486)
  end

  def test_shadowing_block_local_variables
    bug9486 = '[ruby-core:60501] [Bug #9486]'
    assert_equal([:x, :bug9486], tap {|;x| x = x; break local_variables}, bug9486)
  end

  def test_global_variables
    gv = global_variables
    assert_empty(gv.grep(/\A(?!\$)/))
    assert_nil($~)
    assert_not_include(gv, :$1)
    /(\w)(\d)?(.)(.)(.)(.)(.)(.)(.)(.)(\d)?(.)/ =~ "globalglobalglobal"
    assert_not_nil($~)
    gv = global_variables - gv
    assert_include(gv, :$1)
    assert_not_include(gv, :$2)
    assert_not_include(gv, :$11)
    assert_include(gv, :$12)
  end

  def test_global_variable_0
    assert_in_out_err(["-e", "$0='t'*1000;print $0"], "", /\At+\z/, [])
  end

  def test_global_variable_popped
    assert_nothing_raised {
      EnvUtil.suppress_warning {
        eval("$foo; 1")
      }
    }
  end

  def test_constant_popped
    assert_nothing_raised {
      EnvUtil.suppress_warning {
        eval("TestVariable::Gods; 1")
      }
    }
  end

  def test_special_constant_ivars
    [ true, false, :symbol, "dsym#{rand(9999)}".to_sym, 1, 1.0 ].each do |v|
      assert_empty v.instance_variables
      msg = "can't modify frozen #{v.class}"

      assert_raise_with_message(FrozenError, msg) do
        v.instance_variable_set(:@foo, :bar)
      end

      assert_nil EnvUtil.suppress_warning {v.instance_variable_get(:@foo)}
      assert_not_send([v, :instance_variable_defined?, :@foo])

      assert_raise_with_message(FrozenError, msg) do
        v.remove_instance_variable(:@foo)
      end
    end
  end

  def test_local_variables_with_kwarg
    bug11674 = '[ruby-core:71437] [Bug #11674]'
    v = with_kwargs_11(v1:1,v2:2,v3:3,v4:4,v5:5,v6:6,v7:7,v8:8,v9:9,v10:10,v11:11)
    assert_equal(%i(v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11), v, bug11674)
  end

  private
  def with_kwargs_11(v1:, v2:, v3:, v4:, v5:, v6:, v7:, v8:, v9:, v10:, v11:)
    local_variables
  end
end
