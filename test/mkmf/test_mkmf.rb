# frozen_string_literal: false
require 'test/unit'
require 'mkmf'

class TestMkmf < Test::Unit::TestCase
  class TestGlobal < TestMkmf
    main = TOPLEVEL_BINDING.receiver
    MakeMakefile.public_instance_methods(false).each do |m|
      define_method(:"test_global_#{m}") do
        assert_respond_to(main, [m, true])
        assert_not_respond_to(main, [m, false])
      end
    end
  end
end
