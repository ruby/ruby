# frozen_string_literal: true
require 'test/unit'

class Test_Load_Extensions < Test::Unit::TestCase
  ENV_ENABLE_BOX = {'RUBY_BOX' => '1'}

  def test_load_extension
    pend
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      require '-test-/box/yay1'
      assert_equal "1.0.0", Yay.version
      assert_equal "yay", Yay.yay
    end;
  end

  def test_extension_contamination_in_global
    pend
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      require '-test-/box/yay1'
      yay1 = Yay
      assert_equal "1.0.0", Yay.version
      assert_equal "yay", Yay.yay

      require '-test-/box/yay2'
      assert_equal "2.0.0", Yay.version
      v = Yay.yay
      assert(v == "yay" || v == "yaaay") # "yay" on Linux, "yaaay" on macOS, Win32
    end;
  end

  def test_load_extension_in_box
    pend
    assert_separately([ENV_ENABLE_BOX], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      ns = Ruby::Box.new
      ns.require '-test-/box/yay1'
      assert_equal "1.0.0", ns::Yay.version
      assert_raise(NameError) { Yay }
    end;
  end

  def test_different_version_extensions
    pend
    assert_separately([ENV_ENABLE_BOX], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      ns1 = Ruby::Box.new
      ns2 = Ruby::Box.new
      ns1.require('-test-/box/yay1')
      ns2.require('-test-/box/yay2')

      assert_raise(NameError) { Yay }
      assert_not_nil ns1::Yay
      assert_not_nil ns2::Yay
      assert_equal "1.0.0", ns1::Yay::VERSION
      assert_equal "2.0.0", ns2::Yay::VERSION
      assert_equal "1.0.0", ns1::Yay.version
      assert_equal "2.0.0", ns2::Yay.version
    end;
  end

  def test_loading_extensions_from_global_to_local
    pend
    assert_separately([ENV_ENABLE_BOX], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      require '-test-/box/yay1'
      assert_equal "1.0.0", Yay.version
      assert_equal "yay", Yay.yay

      ns = Ruby::Box.new
      ns.require '-test-/box/yay2'
      assert_equal "2.0.0", ns::Yay.version
      assert_equal "yaaay", ns::Yay.yay

      assert_equal "yay", Yay.yay
    end;
  end

  def test_loading_extensions_from_local_to_global
    pend
    assert_separately([ENV_ENABLE_BOX], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      ns = Ruby::Box.new
      ns.require '-test-/box/yay1'
      assert_equal "1.0.0", ns::Yay.version
      assert_equal "yay", ns::Yay.yay


      require '-test-/box/yay2'
      assert_equal "2.0.0", Yay.version
      assert_equal "yaaay", Yay.yay

      assert_equal "yay", ns::Yay.yay
    end;
  end
end
