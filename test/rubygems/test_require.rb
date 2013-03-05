require 'rubygems/test_case'
require 'rubygems'

class TestGemRequire < Gem::TestCase

  def setup
    super

    assert_raises LoadError do
      save_loaded_features do
        require 'test_gem_require_a'
      end
    end
  end

  def assert_require(path)
    assert require(path), "'#{path}' was already required"
  end

  def test_require_is_not_lazy_with_exact_req
    a1 = new_spec "a", "1", {"b" => "= 1"}, "lib/test_gem_require_a.rb"
    b1 = new_spec "b", "1", nil, "lib/b/c.rb"
    b2 = new_spec "b", "2", nil, "lib/b/c.rb"

    install_specs a1, b1, b2

    save_loaded_features do
      assert_require 'test_gem_require_a'
      assert_equal %w(a-1 b-1), loaded_spec_names
      assert_equal unresolved_names, []

      assert_require "b/c"
      assert_equal %w(a-1 b-1), loaded_spec_names
    end
  end

  def test_require_is_lazy_with_inexact_req
    a1 = new_spec "a", "1", {"b" => ">= 1"}, "lib/test_gem_require_a.rb"
    b1 = new_spec "b", "1", nil, "lib/b/c.rb"
    b2 = new_spec "b", "2", nil, "lib/b/c.rb"

    install_specs a1, b1, b2

    save_loaded_features do
      assert_require 'test_gem_require_a'
      assert_equal %w(a-1), loaded_spec_names
      assert_equal unresolved_names, ["b (>= 1)"]

      assert_require "b/c"
      assert_equal %w(a-1 b-2), loaded_spec_names
    end
  end

  def test_require_is_not_lazy_with_one_possible
    a1 = new_spec "a", "1", {"b" => ">= 1"}, "lib/test_gem_require_a.rb"
    b1 = new_spec "b", "1", nil, "lib/b/c.rb"

    install_specs a1, b1

    save_loaded_features do
      assert_require 'test_gem_require_a'
      assert_equal %w(a-1 b-1), loaded_spec_names
      assert_equal unresolved_names, []

      assert_require "b/c"
      assert_equal %w(a-1 b-1), loaded_spec_names
    end
  end

  def test_activate_via_require_respects_loaded_files
    require 'benchmark' # stdlib
    save_loaded_features do
      a1 = new_spec "a", "1", {"b" => ">= 1"}, "lib/test_gem_require_a.rb"
      b1 = new_spec "b", "1", nil, "lib/benchmark.rb"
      b2 = new_spec "b", "2", nil, "lib/benchmark.rb"

      install_specs a1, b1, b2

      require 'test_gem_require_a'
      assert_equal unresolved_names, ["b (>= 1)"]

      refute require('benchmark'), "benchmark should have already been loaded"

      # We detected that we should activate b-2, so we did so, but
      # then original_require decided "I've already got benchmark.rb" loaded.
      # This case is fine because our lazy loading is provided exactly
      # the same behavior as eager loading would have.

      assert_equal %w(a-1 b-2), loaded_spec_names
    end
  end

  def test_already_activated_direct_conflict
    save_loaded_features do
      a1 = new_spec "a", "1", { "b" => "> 0" }
      b1 = new_spec "b", "1", { "c" => ">= 1" }, "lib/ib.rb"
      b2 = new_spec "b", "2", { "c" => ">= 2" }, "lib/ib.rb"
      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec("c", "2", nil, "lib/d.rb")

      install_specs a1, b1, b2, c1, c2

      a1.activate
      c1.activate
      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      assert require("ib")

      assert_equal %w(a-1 b-1 c-1), loaded_spec_names
      assert_equal [], unresolved_names
    end
  end

  def test_multiple_gems_with_the_same_path
    save_loaded_features do
      a1 = new_spec "a", "1", { "b" => "> 0", "x" => "> 0" }
      b1 = new_spec "b", "1", { "c" => ">= 1" }, "lib/ib.rb"
      b2 = new_spec "b", "2", { "c" => ">= 2" }, "lib/ib.rb"
      x1 = new_spec "x", "1", nil, "lib/ib.rb"
      x2 = new_spec "x", "2", nil, "lib/ib.rb"
      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec("c", "2", nil, "lib/d.rb")

      install_specs a1, b1, b2, c1, c2, x1, x2

      a1.activate
      c1.activate
      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)", "x (> 0)"], unresolved_names

      e = assert_raises(Gem::LoadError) do
        require("ib")
      end

      assert_equal "ib found in multiple gems: b, x", e.message
    end
  end

  def test_unable_to_find_good_unresolved_version
    save_loaded_features do
      a1 = new_spec "a", "1", { "b" => "> 0" }
      b1 = new_spec "b", "1", { "c" => ">= 2" }, "lib/ib.rb"
      b2 = new_spec "b", "2", { "c" => ">= 3" }, "lib/ib.rb"

      c1 = new_spec "c", "1", nil, "lib/d.rb"
      c2 = new_spec "c", "2", nil, "lib/d.rb"
      c3 = new_spec "c", "3", nil, "lib/d.rb"

      install_specs a1, b1, b2, c1, c2, c3

      a1.activate
      c1.activate
      assert_equal %w(a-1 c-1), loaded_spec_names
      assert_equal ["b (> 0)"], unresolved_names

      e = assert_raises(Gem::LoadError) do
        require("ib")
      end

      assert_equal "unable to find a version of 'b' to activate", e.message
    end
  end

  def test_default_gem_only
    save_loaded_features do
      default_gem_spec = new_default_spec("default", "2.0.0.0",
                                          nil, "default/gem.rb")
      install_default_specs(default_gem_spec)
      assert_require "default/gem"
      assert_equal %w(default-2.0.0.0), loaded_spec_names
    end
  end

  def test_default_gem_and_normal_gem
    save_loaded_features do
      default_gem_spec = new_default_spec("default", "2.0.0.0",
                                          nil, "default/gem.rb")
      install_default_specs(default_gem_spec)
      normal_gem_spec = new_spec("default", "3.0", nil,
                                 "lib/default/gem.rb")
      install_specs(normal_gem_spec)
      assert_require "default/gem"
      assert_equal %w(default-3.0), loaded_spec_names
    end
  end

  def loaded_spec_names
    Gem.loaded_specs.values.map(&:full_name).sort
  end

  def unresolved_names
    Gem::Specification.unresolved_deps.values.map(&:to_s).sort
  end

  def save_loaded_features
    old_loaded_features = $LOADED_FEATURES.dup
    yield
  ensure
    $LOADED_FEATURES.replace old_loaded_features
  end

end
