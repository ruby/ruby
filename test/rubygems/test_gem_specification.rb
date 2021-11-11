# frozen_string_literal: true
require 'benchmark'
require_relative 'helper'
require 'date'
require 'pathname'
require 'stringio'
require 'rubygems/ext'
require 'rubygems/specification'
require 'rubygems/installer'
require 'rubygems/platform'

class TestGemSpecification < Gem::TestCase
  LEGACY_YAML_SPEC = <<-EOF.freeze
--- !ruby/object:Gem::Specification
rubygems_version: "1.0"
name: keyedlist
version: !ruby/object:Gem::Version
  version: 0.4.0
date: 2004-03-28 15:37:49.828000 +02:00
platform:
summary: A Hash which automatically computes keys.
require_paths:
  - lib
files:
  - lib/keyedlist.rb
autorequire: keyedlist
author: Florian Gross
email: flgr@ccan.de
has_rdoc: true
  EOF

  LEGACY_RUBY_SPEC = <<-EOF.freeze
Gem::Specification.new do |s|
  s.name = %q{keyedlist}
  s.version = %q{0.4.0}
  s.has_rdoc = true
  s.summary = %q{A Hash which automatically computes keys.}
  s.files = [%q{lib/keyedlist.rb}]
  s.require_paths = [%q{lib}]
  s.autorequire = %q{keyedlist}
  s.author = %q{Florian Gross}
  s.email = %q{flgr@ccan.de}
end
  EOF

  def make_spec_c1
    @c1 = util_spec 'a', '1' do |s|
      s.executable = 'exec'
      s.extensions << 'ext/a/extconf.rb'
      s.test_file = 'test/suite.rb'
      s.requirements << 'A working computer'
      s.license = 'MIT'

      s.add_dependency 'rake', '> 0.4'
      s.add_dependency 'jabber4r', '> 0.0.0'
      s.add_dependency 'pqa', ['> 0.4', '<= 0.6']

      s.mark_version
      s.files = %w[lib/code.rb]
    end
  end

  def ext_spec(platform: Gem::Platform::RUBY)
    @ext = util_spec 'ext', '1' do |s|
      s.executable = 'exec'
      s.test_file = 'test/suite.rb'
      s.extensions = %w[ext/extconf.rb]
      s.license = 'MIT'
      s.platform = platform

      s.mark_version
      s.files = %w[lib/code.rb]
      s.installed_by_version = v('2.2')
    end
  end

  def assert_date(date)
    assert_kind_of Time, date
    assert_equal [0, 0, 0], [date.hour, date.min, date.sec]
    assert_operator (Gem::Specification::TODAY..Time.now), :cover?, date
  end

  def setup
    super

    # Setting `@default_source_date_epoch` to `nil` effectively resets the
    # value used for `Gem.source_date_epoch` whenever `$SOURCE_DATE_EPOCH`
    # is not set.
    Gem.instance_variable_set(:'@default_source_date_epoch', nil)

    @a1 = util_spec 'a', '1' do |s|
      s.executable = 'exec'
      s.test_file = 'test/suite.rb'
      s.requirements << 'A working computer'
      s.license = 'MIT'

      s.mark_version
      s.files = %w[lib/code.rb]
    end

    @a2 = util_spec 'a', '2' do |s|
      s.files = %w[lib/code.rb]
    end

    @a3 = util_spec 'a', '3' do |s|
      s.metadata['allowed_push_host'] = "https://privategemserver.com"
    end

    @current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
  end

  def test_self_find_active_stub_by_path
    spec = util_spec('a', '1', nil, 'lib/foo.rb')
    spec.activated = true

    # There used to be a bug (introduced in a9c1aaf) when Gem::Specification
    # objects are present in the @stubs collection. This test verifies that
    # this scenario works correctly.
    Gem::Specification.all = [spec]
    assert_equal spec, Gem::Specification.find_active_stub_by_path('foo')
  end

  def test_self_activate
    foo = util_spec 'foo', '1'

    assert_activate %w[foo-1], foo
  end

  def test_self_activate_ambiguous_direct
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec("b", "1", { "c" => ">= 1" }, "lib/d#{$$}.rb")
    b2 = util_spec("b", "2", { "c" => ">= 2" }, "lib/d#{$$}.rb")
    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"

    Gem::Specification.reset
    install_specs c1, c2, b1, b2, a1

    a1.activate
    assert_equal %w[a-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names

    require "d#{$$}"

    assert_equal %w[a-1 b-2 c-2], loaded_spec_names
    assert_equal [], unresolved_names
  end

  def test_find_in_unresolved_tree_is_not_exponentiental
    num_of_pkg = 7
    num_of_version_per_pkg = 3
    packages = (0..num_of_pkg).map do |pkgi|
      (0..num_of_version_per_pkg).map do |pkg_version|
        deps = Hash[((pkgi + 1)..num_of_pkg).map do |deppkgi|
                      ["pkg#{deppkgi}", ">= 0"]
                    end]
        util_spec "pkg#{pkgi}", pkg_version.to_s, deps
      end
    end
    base = util_spec "pkg_base", "1", {"pkg0" => ">= 0"}

    Gem::Specification.reset
    install_specs(*packages.flatten.reverse)
    install_specs base
    base.activate

    tms = Benchmark.measure do
      assert_raise(LoadError) { require 'no_such_file_foo' }
    end
    assert_operator tms.total, :<=, 10
  end

  def test_self_activate_ambiguous_indirect
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 1"
    b2 = util_spec "b", "2", "c" => ">= 2"
    c1 = util_spec "c", "1", nil, "lib/d#{$$}.rb"
    c2 = util_spec "c", "2", nil, "lib/d#{$$}.rb"

    install_specs c1, c2, b1, b2, a1

    a1.activate
    assert_equal %w[a-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names

    require "d#{$$}"

    assert_equal %w[a-1 b-2 c-2], loaded_spec_names
    assert_equal [], unresolved_names
  end

  def test_self_activate_ambiguous_indirect_conflict
    a1 = util_spec "a", "1", "b" => "> 0"
    a2 = util_spec "a", "2", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 1"
    b2 = util_spec "b", "2", "c" => ">= 2"
    c1 = util_spec "c", "1", nil, "lib/d#{$$}.rb"
    c2 = util_spec("c", "2", { "a" => "1" }, "lib/d#{$$}.rb") # conflicts with a-2

    install_specs c1, b1, a1, a2, c2, b2

    a2.activate
    assert_equal %w[a-2], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names

    require "d#{$$}"

    assert_equal %w[a-2 b-1 c-1], loaded_spec_names
    assert_equal [], unresolved_names
  end

  def test_self_activate_ambiguous_unrelated
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 1"
    b2 = util_spec "b", "2", "c" => ">= 2"
    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb"

    install_specs d1, c1, c2, b1, b2, a1

    a1.activate
    assert_equal %w[a-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names

    require "d#{$$}"

    assert_equal %w[a-1 d-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names
  end

  def test_require_should_prefer_latest_gem_level1
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 0" # unresolved
    b2 = util_spec "b", "2", "c" => ">= 0"
    c1 = util_spec "c", "1", nil, "lib/c#{$$}.rb" # 1st level
    c2 = util_spec "c", "2", nil, "lib/c#{$$}.rb"

    install_specs c1, c2, b1, b2, a1

    a1.activate

    require "c#{$$}"

    assert_equal %w[a-1 b-2 c-2], loaded_spec_names
  end

  def test_require_should_prefer_latest_gem_level2
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 0" # unresolved
    b2 = util_spec "b", "2", "c" => ">= 0"
    c1 = util_spec "c", "1", "d" => ">= 0" # 1st level
    c2 = util_spec "c", "2", "d" => ">= 0"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb" # 2nd level
    d2 = util_spec "d", "2", nil, "lib/d#{$$}.rb"

    install_specs d1, d2, c1, c2, b1, b2, a1

    a1.activate

    require "d#{$$}"

    assert_equal %w[a-1 b-2 c-2 d-2], loaded_spec_names
  end

  def test_require_finds_in_2nd_level_indirect
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 0" # unresolved
    b2 = util_spec "b", "2", "c" => ">= 0"
    c1 = util_spec "c", "1", "d" => "<= 2" # 1st level
    c2 = util_spec "c", "2", "d" => "<= 2"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb" # 2nd level
    d2 = util_spec "d", "2", nil, "lib/d#{$$}.rb"
    d3 = util_spec "d", "3", nil, "lib/d#{$$}.rb"

    install_specs d1, d2, d3, c1, c2, b1, b2, a1

    a1.activate

    require "d#{$$}"

    assert_equal %w[a-1 b-2 c-2 d-2], loaded_spec_names
  end

  def test_require_should_prefer_reachable_gems
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 0" # unresolved
    b2 = util_spec "b", "2", "c" => ">= 0"
    c1 = util_spec "c", "1", "d" => "<= 2" # 1st level
    c2 = util_spec "c", "2", "d" => "<= 2"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb" # 2nd level
    d2 = util_spec "d", "2", nil, "lib/d#{$$}.rb"
    d3 = util_spec "d", "3", nil, "lib/d#{$$}.rb"
    e  = util_spec "anti_d", "1", nil, "lib/d#{$$}.rb"

    install_specs d1, d2, d3, e, c1, c2, b1, b2, a1

    a1.activate

    require "d#{$$}"

    assert_equal %w[a-1 b-2 c-2 d-2], loaded_spec_names
  end

  def test_require_should_not_conflict
    base = util_spec "0", "1", "A" => ">= 1"
    a1 = util_spec "A", "1", {"c" => ">= 2", "b" => "> 0"}, "lib/a.rb"
    a2 = util_spec "A", "2", {"c" => ">= 2", "b" => "> 0"}, "lib/a.rb"
    b1 = util_spec "b", "1", {"c" => "= 1"}, "lib/d#{$$}.rb"
    b2 = util_spec "b", "2", {"c" => "= 2"}, "lib/d#{$$}.rb"
    c1 = util_spec "c", "1", {}, "lib/c.rb"
    c2 = util_spec "c", "2", {}, "lib/c.rb"
    c3 = util_spec "c", "3", {}, "lib/c.rb"

    install_specs c1, c2, c3, b1, b2, a1, a2, base

    base.activate
    assert_equal %w[0-1], loaded_spec_names
    assert_equal ["A (>= 1)"], unresolved_names

    require "d#{$$}"

    assert_equal %w[0-1 A-2 b-2 c-2], loaded_spec_names
    assert_equal [], unresolved_names
  end

  def test_inner_clonflict_in_indirect_gems
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 1" # unresolved
    b2 = util_spec "b", "2", "c" => ">= 1", "d" => "< 3"
    c1 = util_spec "c", "1", "d" => "<= 2" # 1st level
    c2 = util_spec "c", "2", "d" => "<= 2"
    c3 = util_spec "c", "3", "d" => "<= 3"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb" # 2nd level
    d2 = util_spec "d", "2", nil, "lib/d#{$$}.rb"
    d3 = util_spec "d", "3", nil, "lib/d#{$$}.rb"

    install_specs d1, d2, d3, c1, c2, c3, b1, b2, a1

    a1.activate

    require "d#{$$}"

    assert_includes [%w[a-1 b-2 c-3 d-2],%w[a-1 b-2 d-2]], loaded_spec_names
  end

  def test_inner_clonflict_in_indirect_gems_reversed
    a1 = util_spec "a", "1", "b" => "> 0"
    b1 = util_spec "b", "1", "xc" => ">= 1" # unresolved
    b2 = util_spec "b", "2", "xc" => ">= 1", "d" => "< 3"
    c1 = util_spec "xc", "1", "d" => "<= 3" # 1st level
    c2 = util_spec "xc", "2", "d" => "<= 2"
    c3 = util_spec "xc", "3", "d" => "<= 3"
    d1 = util_spec "d", "1", nil, "lib/d#{$$}.rb" # 2nd level
    d2 = util_spec "d", "2", nil, "lib/d#{$$}.rb"
    d3 = util_spec "d", "3", nil, "lib/d#{$$}.rb"

    install_specs d1, d2, d3, c1, c2, c3, b1, b2, a1

    a1.activate

    require "d#{$$}"

    assert_includes [%w[a-1 b-2 d-2 xc-3], %w[a-1 b-2 d-2]], loaded_spec_names
  end

  ##
  # [A] depends on
  #     [C]  = 1.0 depends on
  #         [B] = 2.0
  #     [B] ~> 1.0 (satisfied by 1.0)

  def test_self_activate_checks_dependencies
    a = util_spec 'a', '1.0'
    a.add_dependency 'c', '= 1.0'
    a.add_dependency 'b', '~> 1.0'

    b1 = util_spec 'b', '1.0'
    b2 = util_spec 'b', '2.0'
    c  = util_spec 'c', '1.0', 'b' => '= 2.0'
    install_specs b1, b2, c, a

    e = assert_raise Gem::LoadError do
      assert_activate nil, a, c, "b"
    end

    expected = "can't satisfy 'b (~> 1.0)', already activated 'b-2.0'"
    assert_equal expected, e.message
  end

  ##
  # [A] depends on
  #     [B] ~> 1.0 (satisfied by 1.0)
  #     [C]  = 1.0 depends on
  #         [B] = 2.0

  def test_self_activate_divergent
    a  = util_spec 'a', '1.0', 'b' => '~> 1.0', 'c' => '= 1.0'
    b1 = util_spec 'b', '1.0'
    b2 = util_spec 'b', '2.0'
    c  = util_spec 'c', '1.0', 'b' => '= 2.0'

    install_specs b1, b2, c, a

    e = assert_raise Gem::ConflictError do
      assert_activate nil, a, c, "b"
    end

    assert_match(/Unable to activate c-1.0,/, e.message)
    assert_match(/because b-1.0 conflicts with b .= 2.0/, e.message)
  end

  ##
  # DOC

  def test_self_activate_old_required
    e1, = util_spec 'e', '1', 'd' => '= 1'
    @d1 = util_spec 'd', '1'
    @d2 = util_spec 'd', '2'

    install_specs @d1, @d2, e1

    assert_activate %w[d-1 e-1], e1, "d"
  end

  ##
  # DOC

  def test_self_activate_platform_alternate
    @x1_m = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @x1_o = util_spec 'x', '1' do |s|
      s.platform = Gem::Platform.new %w[cpu other_platform 1]
    end

    @w1 = util_spec 'w', '1', 'x' => nil

    util_set_arch 'cpu-my_platform1'
    install_specs @x1_m, @x1_o, @w1

    assert_activate %w[x-1-cpu-my_platform-1 w-1], @w1, @x1_m
  end

  ##
  # DOC

  def test_self_activate_platform_bump
    @y1 = util_spec 'y', '1'

    @y1_1_p = util_spec 'y', '1.1' do |s|
      s.platform = Gem::Platform.new %w[cpu my_platform 1]
    end

    @z1 = util_spec 'z', '1', 'y' => nil
    install_specs @y1, @y1_1_p, @z1

    assert_activate %w[y-1 z-1], @z1, @y1
  end

  ##
  # [C] depends on
  #     [A] = 1.a
  #     [B] = 1.0 depends on
  #         [A] >= 0 (satisfied by 1.a)

  def test_self_activate_prerelease
    @c1_pre = util_spec 'c', '1.a', "a" => "1.a", "b" => "1"
    @a1_pre = util_spec 'a', '1.a'
    @b1     = util_spec 'b', '1' do |s|
      s.add_dependency 'a'
      s.add_development_dependency 'aa'
    end
    install_specs @a1_pre, @b1, @c1_pre

    assert_activate %w[a-1.a b-1 c-1.a], @c1_pre, @a1_pre, @b1
  end

  def test_self_activate_via_require
    a1 = util_spec "a", "1", "b" => "= 1"
    b1 = util_spec "b", "1", nil, "lib/b/c.rb"
    b2 = util_spec "b", "2", nil, "lib/b/c.rb"

    install_specs b1, b2, a1

    a1.activate
    require "b/c"

    assert_equal %w[a-1 b-1], loaded_spec_names
  end

  def test_self_activate_via_require_wtf
    a1 = util_spec "a", "1", "b" => "> 0", "d" => "> 0" # this
    b1 = util_spec "b", "1", { "c" => ">= 1" }, "lib/b#{$$}.rb"
    b2 = util_spec "b", "2", { "c" => ">= 2" }, "lib/b#{$$}.rb" # this
    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2" # this
    d1 = util_spec "d", "1", { "c" => "< 2" },  "lib/d#{$$}.rb"
    d2 = util_spec "d", "2", { "c" => "< 2" },  "lib/d#{$$}.rb" # this

    install_specs c1, c2, b1, b2, d1, d2, a1

    a1.activate

    assert_equal %w[a-1], loaded_spec_names
    assert_equal ["b (> 0)", "d (> 0)"], unresolved_names

    require "b#{$$}"

    e = assert_raise Gem::LoadError do
      require "d#{$$}"
    end

    assert_equal "unable to find a version of 'd' to activate", e.message

    assert_equal %w[a-1 b-2 c-2], loaded_spec_names
    assert_equal ["d (> 0)"], unresolved_names
  end

  def test_self_activate_deep_unambiguous
    a1 = util_spec "a", "1", "b" => "= 1"
    b1 = util_spec "b", "1", "c" => "= 1"
    b2 = util_spec "b", "2", "c" => "= 2"
    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"

    install_specs c1, c2, b1, b2, a1

    a1.activate
    assert_equal %w[a-1 b-1 c-1], loaded_spec_names
  end

  def test_self_activate_loaded
    foo = util_spec 'foo', '1'

    assert foo.activate
    refute foo.activate
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 2.0)
  # [C] depends on nothing

  def test_self_activate_unrelated
    a = util_spec 'a', '1.0', 'b' => '>= 1.0'
    b = util_spec 'b', '1.0'
    c = util_spec 'c', '1.0'
    install_specs b, c, a

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 2.0)
  #     [C]  = 1.0 depends on
  #         [B] ~> 1.0
  #
  # and should resolve using b-1.0
  # TODO: move these to specification

  def test_self_activate_over
    a = util_spec 'a', '1.0', 'b' => '>= 1.0', 'c' => '= 1.0'
    install_specs util_spec 'b', '1.0'
    install_specs util_spec 'b', '1.1'
    install_specs util_spec 'b', '2.0'
    install_specs util_spec 'c', '1.0', 'b' => '~> 1.0'
    install_specs a

    a.activate

    assert_equal %w[a-1.0 c-1.0], loaded_spec_names
    assert_equal ["b (>= 1.0, ~> 1.0)"], unresolved_names
  end

  ##
  # [A] depends on
  #     [B] ~> 1.0 (satisfied by 1.1)
  #     [C]  = 1.0 depends on
  #         [B] = 1.0
  #
  # and should resolve using b-1.0
  #
  # TODO: this is not under, but over... under would require depth
  # first resolve through a dependency that is later pruned.

  def test_self_activate_under
    a    = util_spec 'a', '1.0', 'b' => '~> 1.0', 'c' => '= 1.0'
    b1   = util_spec 'b', '1.0'
    b1_1 = util_spec 'b', '1.1'
    c    = util_spec 'c', '1.0', 'b' => '= 1.0'

    install_specs b1, b1_1, c, a

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  ##
  # [A1] depends on
  #    [B] > 0 (satisfied by 2.0)
  # [B1] depends on
  #    [C] > 0 (satisfied by 1.0)
  # [B2] depends on nothing!
  # [C1] depends on nothing

  def test_self_activate_dropped
    a1 = util_spec 'a', '1', 'b' => nil
    b1 = util_spec 'b', '1', 'c' => nil
    b2 = util_spec 'b', '2'
    c1 = util_spec 'c', '1'
    install_specs c1, b1, b2, a1

    assert_activate %w[b-2 a-1], a1, "b"
  end

  ##
  # [A] depends on
  #     [B] >= 1.0 (satisfied by 1.1) depends on
  #         [Z]
  #     [C] >= 1.0 depends on
  #         [B] = 1.0
  #
  # and should backtrack to resolve using b-1.0, pruning Z from the
  # resolve.

  def test_self_activate_raggi_the_edgecase_generator
    a    = util_spec 'a', '1.0', 'b' => '>= 1.0', 'c' => '>= 1.0'
    b1   = util_spec 'b', '1.0'
    b1_0 = util_spec 'b', '1.1', 'z' => '>= 1.0'
    c    = util_spec 'c', '1.0', 'b' => '= 1.0'
    z    = util_spec 'z', '1'

    install_specs z, b1, b1_0, c, z

    assert_activate %w[b-1.0 c-1.0 a-1.0], a, c, "b"
  end

  def test_self_activate_conflict
    install_specs util_spec 'b', '1.0'
    install_specs util_spec 'b', '2.0'

    gem "b", "= 1.0"

    assert_raise Gem::LoadError do
      gem "b", "= 2.0"
    end
  end

  def test_self_all_equals
    a = util_spec "foo", "1", nil, "lib/foo.rb"

    install_specs a
    Gem::Specification.all = [a]

    assert_equal a, Gem::Specification.find_inactive_by_path('foo')
  end

  def test_self_attribute_names
    expected_value = %w[
      authors
      autorequire
      bindir
      cert_chain
      date
      dependencies
      description
      email
      executables
      extensions
      extra_rdoc_files
      files
      homepage
      licenses
      metadata
      name
      platform
      post_install_message
      rdoc_options
      require_paths
      required_ruby_version
      required_rubygems_version
      requirements
      rubygems_version
      signing_key
      specification_version
      summary
      test_files
      version
    ]

    actual_value = Gem::Specification.attribute_names.map {|a| a.to_s }.sort

    assert_equal expected_value, actual_value
  end

  def test_self__load_future
    spec = Gem::Specification.new
    spec.name = 'a'
    spec.version = '1'
    spec.specification_version = @current_version + 1

    load_spec = Marshal.load Marshal.dump(spec)

    assert_equal 'a', load_spec.name
    assert_equal Gem::Version.new(1), load_spec.version
    assert_equal @current_version, load_spec.specification_version
  end

  def test_self_from_yaml
    @a1.instance_variable_set :@specification_version, nil

    spec = Gem::Specification.from_yaml @a1.to_yaml

    assert_equal Gem::Specification::NONEXISTENT_SPECIFICATION_VERSION,
                 spec.specification_version
  end

  def test_self_from_yaml_cleans_up_Date_objects
    yaml = <<-YAML
--- !ruby/object:Gem::Specification
rubygems_version: 0.8.1
specification_version: 1
name: diff-lcs
version: !ruby/object:Gem::Version
  version: 1.1.2
date: 2004-10-20
summary: Provides a list of changes that represent the difference between two sequenced collections.
require_paths:
  - lib
author: Austin Ziegler
email: diff-lcs@halostatue.ca
homepage: http://rubyforge.org/projects/ruwiki/
description: "Test"
bindir: bin
has_rdoc: true
required_ruby_version: !ruby/object:Gem::Version::Requirement
  requirements:
    -
      - ">="
      - !ruby/object:Gem::Version
        version: 1.8.1
  version:
platform: ruby
files:
  - tests/00test.rb
rdoc_options:
  - "--title"
  - "Diff::LCS -- A Diff Algorithm"
  - "--main"
  - README
  - "--line-numbers"
extra_rdoc_files:
  - README
  - ChangeLog
  - Install
executables:
  - ldiff
  - htmldiff
extensions: []
requirements: []
dependencies: []
    YAML

    spec = Gem::Specification.from_yaml yaml

    assert_kind_of Time, spec.date
  end

  def test_self_load
    full_path = @a2.spec_file
    write_file full_path do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_relative
    File.open 'a-2.gemspec', 'w' do |io|
      io.write @a2.to_ruby_for_cache
    end

    spec = Gem::Specification.load 'a-2.gemspec'

    @a2.files.clear

    assert_equal @a2, spec

    assert_equal File.join(@tempdir, 'a-2.gemspec'), spec.loaded_from
  end

  if RUBY_ENGINE == 'ruby' and RUBY_VERSION < '2.7'
    def test_self_load_tainted
      full_path = @a2.spec_file
      write_file full_path do |io|
        io.write @a2.to_ruby_for_cache
      end

      full_path.taint
      loader = Thread.new { $SAFE = 1; Gem::Specification.load full_path }
      spec = loader.value

      @a2.files.clear

      assert_equal @a2, spec

    ensure
      $SAFE = 0
    end
  end

  def test_self_load_escape_curly
    @a2.name = 'a};raise "improper escaping";%q{'

    full_path = @a2.spec_file
    begin
      write_file full_path do |io|
        io.write @a2.to_ruby_for_cache
      end
    rescue Errno::EINVAL
      pend "cannot create '#{full_path}' on this platform"
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_escape_interpolation
    @a2.name = 'a#{raise %<improper escaping>}'

    full_path = @a2.spec_file
    begin
      write_file full_path do |io|
        io.write @a2.to_ruby_for_cache
      end
    rescue Errno::EINVAL
      pend "cannot create '#{full_path}' on this platform"
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_escape_quote
    @a2.name = 'a";raise "improper escaping";"'

    full_path = @a2.spec_file
    begin
      write_file full_path do |io|
        io.write @a2.to_ruby_for_cache
      end
    rescue Errno::EINVAL
      pend "cannot create '#{full_path}' on this platform"
    end

    spec = Gem::Specification.load full_path

    @a2.files.clear

    assert_equal @a2, spec
  end

  def test_self_load_utf8_with_ascii_encoding
    int_enc = Encoding.default_internal
    silence_warnings { Encoding.default_internal = 'US-ASCII' }

    spec2 = @a2.dup
    bin = "\u5678".dup
    spec2.authors = [bin]
    full_path = spec2.spec_file
    write_file full_path do |io|
      io.write spec2.to_ruby_for_cache.force_encoding('BINARY').sub("\\u{5678}", bin.force_encoding('BINARY'))
    end

    spec = Gem::Specification.load full_path

    spec2.files.clear

    assert_equal spec2, spec
  ensure
    silence_warnings { Encoding.default_internal = int_enc }
  end

  def test_self_load_legacy_ruby
    spec = Gem::Deprecate.skip_during do
      eval LEGACY_RUBY_SPEC
    end
    assert_equal 'keyedlist', spec.name
    assert_equal '0.4.0', spec.version.to_s
    assert_kind_of Time, spec.date
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new('1'))
    assert_equal false, spec.has_unit_tests?
  end

  def test_self_normalize_yaml_input_with_183_yaml
    input = "!ruby/object:Gem::Specification "
    assert_equal "--- #{input}", Gem::Specification.normalize_yaml_input(input)
  end

  def test_self_normalize_yaml_input_with_non_183_yaml
    input = "--- !ruby/object:Gem::Specification "
    assert_equal input, Gem::Specification.normalize_yaml_input(input)
  end

  def test_self_normalize_yaml_input_with_183_io
    input = "!ruby/object:Gem::Specification "
    assert_equal "--- #{input}",
      Gem::Specification.normalize_yaml_input(StringIO.new(input))
  end

  def test_self_normalize_yaml_input_with_non_183_io
    input = "--- !ruby/object:Gem::Specification "
    assert_equal input,
      Gem::Specification.normalize_yaml_input(StringIO.new(input))
  end

  def test_self_normalize_yaml_input_with_192_yaml
    input = "--- !ruby/object:Gem::Specification \nblah: !!null \n"
    expected = "--- !ruby/object:Gem::Specification \nblah: \n"

    assert_equal expected, Gem::Specification.normalize_yaml_input(input)
  end

  def test_self_outdated
    spec_fetcher do |fetcher|
      fetcher.download 'a', 4

      fetcher.spec 'a', 3
    end

    assert_equal %w[a], Gem::Specification.outdated
  end

  def test_self_outdated_and_latest_remotes
    specs = spec_fetcher do |fetcher|
      fetcher.download 'a', 4
      fetcher.download 'b', 3

      fetcher.spec 'a', '3.a'
      fetcher.spec 'b', 2
    end

    expected = [
      [specs['a-3.a'], v(4)],
      [specs['b-2'],   v(3)],
    ]

    assert_equal expected, Gem::Specification.outdated_and_latest_version.to_a
  end

  def test_self_remove_spec
    install_specs @a1

    assert_includes Gem::Specification.all_names, 'a-1'
    assert_includes Gem::Specification.stubs.map {|s| s.full_name }, 'a-1'

    uninstall_gem @a1
    Gem::Specification.reset

    refute_includes Gem::Specification.all_names, 'a-1'
    refute_includes Gem::Specification.stubs.map {|s| s.full_name }, 'a-1'
  end

  def test_self_remove_spec_removed
    File.open @a1.spec_file, 'w' do |io|
      io.write @a1.to_ruby
    end

    Gem::Specification.reset

    FileUtils.rm @a1.spec_file # bug #698

    Gem::Specification.reset

    refute_includes Gem::Specification.all_names, 'a-1'
    refute_includes Gem::Specification.stubs.map {|s| s.full_name }, 'a-1'
  end

  def test_self_stubs_for_lazy_loading
    Gem.loaded_specs.clear
    Gem::Specification.class_variable_set(:@@stubs, nil)

    dir_standard_specs = File.join Gem.dir, 'specifications'

    save_gemspec('a-1', '1', dir_standard_specs){|s| s.name = 'a' }
    save_gemspec('b-1', '1', dir_standard_specs){|s| s.name = 'b' }

    assert_equal ['a-1'], Gem::Specification.stubs_for('a').map {|s| s.full_name }
    assert_equal 1, Gem::Specification.class_variable_get(:@@stubs_by_name).length
    assert_equal ['b-1'], Gem::Specification.stubs_for('b').map {|s| s.full_name }
    assert_equal 2, Gem::Specification.class_variable_get(:@@stubs_by_name).length

    assert_equal(
      Gem::Specification.stubs_for('a').map {|s| s.object_id },
      Gem::Specification.stubs_for('a').map {|s| s.object_id }
    )

    Gem.loaded_specs.delete 'a'
    Gem.loaded_specs.delete 'b'
    Gem::Specification.class_variable_set(:@@stubs, nil)
  end

  def test_self_stubs_for_no_lazy_loading_after_all_specs_setup
    Gem::Specification.all = [util_spec('a', '1')]

    save_gemspec('b-1', '1', File.join(Gem.dir, 'specifications')){|s| s.name = 'b' }

    assert_equal [], Gem::Specification.stubs_for('b').map {|s| s.full_name }
  end

  def test_self_stubs_for_mult_platforms
    # gems for two different platforms are installed with --user-install
    # the correct one should be returned in the array

    orig_platform = Gem.platforms.dup

    # create user spec
    user_spec_dir = File.join Gem.user_dir, 'specifications'
    FileUtils.mkdir_p(user_spec_dir) unless Dir.exist? user_spec_dir
    # dirs doesn't include user ?
    Gem::Specification.dirs << user_spec_dir

    gem = 'mingw'
    v   = '1.1.1'
    platforms = ['x86-mingw32', 'x64-mingw32']

    #create specs
    platforms.each do |plat|
      spec = Gem::Specification.new(gem, v) {|s| s.platform = plat }
      File.open File.join(user_spec_dir, "#{gem}-#{v}-#{plat}.gemspec"), 'w' do |io|
        io.write spec.to_ruby
      end
    end

    platforms.each do |plat|
      cur_plat = Gem::Platform.new plat
      Gem.platforms = ['ruby', cur_plat]

      Gem::Specification.class_variable_set :@@stubs, nil
      Gem::Specification.stubs if plat == platforms.last # test loading via stubs
      t = Gem::Specification.stubs_for 'mingw'

      assert_equal 1, t.length
      assert_equal cur_plat, t.first.platform
    end

    Gem.platforms = orig_platform
  end

  def test_self_stubs_returns_only_specified_named_specs
    dir_standard_specs = File.join Gem.dir, 'specifications'

    save_gemspec('a-1', '1', dir_standard_specs){|s| s.name = 'a' }
    save_gemspec('a-2', '2', dir_standard_specs){|s| s.name = 'a' }
    save_gemspec('a-a', '3', dir_standard_specs){|s| s.name = 'a-a' }

    assert_equal ['a-1', 'a-2'], Gem::Specification.stubs_for('a').map(&:full_name).sort
  end

  def test_handles_private_null_type
    path = File.expand_path "../data/null-type.gemspec.rz", __FILE__

    data = Marshal.load Gem::Util.inflate(Gem.read_binary(path))

    assert_nil data.signing_key
  end

  def test_initialize
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"
    end

    assert_equal "blah", spec.name
    assert_equal "1.3.5", spec.version.to_s
    assert_equal Gem::Platform::RUBY, spec.platform
    assert_nil       spec.summary
    assert_equal [], spec.files

    assert_equal [], spec.test_files
    assert_equal [], spec.rdoc_options
    assert_equal [], spec.extra_rdoc_files
    assert_equal [], spec.executables
    assert_equal [], spec.extensions
    assert_equal [], spec.requirements
    assert_equal [], spec.dependencies
    assert_equal 'bin', spec.bindir
    assert_equal '>= 0', spec.required_ruby_version.to_s
    assert_equal '>= 0', spec.required_rubygems_version.to_s
  end

  def test_initialize_future
    version = Gem::Specification::CURRENT_SPECIFICATION_VERSION + 1
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"

      s.specification_version = version

      s.new_unknown_attribute = "a value"
    end

    assert_equal "blah", spec.name
    assert_equal "1.3.5", spec.version.to_s
  end

  def test_initialize_copy
    spec = Gem::Specification.new do |s|
      s.name = "blah"
      s.version = "1.3.5"
      s.summary = 'summary'
      s.description = 'description'
      s.authors = 'author a', 'author b'
      s.licenses = 'BSD-2-Clause'
      s.files = 'lib/file.rb'
      s.test_files = 'test/file.rb'
      s.rdoc_options = '--foo'
      s.extra_rdoc_files = 'README.txt'
      s.executables = 'exec'
      s.extensions = 'ext/extconf.rb'
      s.requirements = 'requirement'
      s.add_dependency 'some_gem'
    end

    dup_spec = spec.dup

    assert_equal "blah", spec.name
    assert_same  spec.name, dup_spec.name

    assert_equal "1.3.5", spec.version.to_s
    assert_same spec.version, dup_spec.version

    assert_equal Gem::Platform::RUBY, spec.platform
    assert_same spec.platform, dup_spec.platform

    assert_equal 'summary', spec.summary
    assert_same spec.summary, dup_spec.summary

    assert_equal %w[README.txt bin/exec ext/extconf.rb lib/file.rb
                    test/file.rb].sort,
                 spec.files
    refute_same spec.files, dup_spec.files, 'files'

    assert_equal %w[test/file.rb], spec.test_files
    refute_same spec.test_files, dup_spec.test_files, 'test_files'

    assert_equal %w[--foo], spec.rdoc_options
    refute_same spec.rdoc_options, dup_spec.rdoc_options, 'rdoc_options'

    assert_equal %w[README.txt], spec.extra_rdoc_files
    refute_same spec.extra_rdoc_files, dup_spec.extra_rdoc_files,
                'extra_rdoc_files'

    assert_equal %w[exec], spec.executables
    refute_same spec.executables, dup_spec.executables, 'executables'

    assert_equal %w[ext/extconf.rb], spec.extensions
    refute_same spec.extensions, dup_spec.extensions, 'extensions'

    assert_equal %w[requirement], spec.requirements
    refute_same spec.requirements, dup_spec.requirements, 'requirements'

    assert_equal [Gem::Dependency.new('some_gem', Gem::Requirement.default)],
                 spec.dependencies
    refute_same spec.dependencies, dup_spec.dependencies, 'dependencies'

    assert_equal 'bin', spec.bindir
    assert_same spec.bindir, dup_spec.bindir

    assert_equal '>= 0', spec.required_ruby_version.to_s
    assert_same spec.required_ruby_version, dup_spec.required_ruby_version

    assert_equal '>= 0', spec.required_rubygems_version.to_s
    assert_same spec.required_rubygems_version,
                dup_spec.required_rubygems_version
  end

  def test_initialize_copy_broken
    spec = Gem::Specification.new do |s|
      s.name = 'a'
      s.version = '1'
    end

    spec.instance_variable_set :@licenses, (class << (Object.new);self;end)
    spec.loaded_from = '/path/to/file'

    e = assert_raise Gem::FormatException do
      spec.dup
    end

    assert_equal 'a-1 has an invalid value for @licenses', e.message
    assert_equal '/path/to/file', e.file_path
  end

  def test_initialize_prerelease_version_before_name
    spec = Gem::Specification.new do |s|
      s.version = '1.0.0.dev'
      s.name = 'a'
    end

    assert_equal "a", spec.name
    assert_equal "1.0.0.dev", spec.version.to_s
  end

  def test__dump
    @a2.platform = Gem::Platform.local
    @a2.instance_variable_set :@original_platform, 'old_platform'

    data = Marshal.dump @a2

    same_spec = Marshal.load data

    assert_equal 'old_platform', same_spec.original_platform
  end

  def test_activate
    @a2.activate

    assert @a2.activated?
  end

  def test_add_dependency_with_type
    gem = util_spec "awesome", "1.0" do |awesome|
      awesome.add_dependency true
      awesome.add_dependency :gem_name
    end

    assert_equal %w[true gem_name], gem.dependencies.map {|dep| dep.name }
  end

  def test_add_dependency_from_existing_dependency
    dep  = Gem::Dependency.new("existing_dep", Gem::Requirement.new('> 1'), :runtime)
    spec = Gem::Specification.new {|s| s.add_dependency dep }
    assert_equal dep, spec.dependencies.first
  end

  def test_add_dependency_with_type_explicit
    gem = util_spec "awesome", "1.0" do |awesome|
      awesome.add_development_dependency "monkey"
    end

    monkey = gem.dependencies.detect {|d| d.name == "monkey" }
    assert_equal(:development, monkey.type)
  end

  def test_author
    assert_equal 'A User', @a1.author
  end

  def test_authors
    assert_equal ['A User'], @a1.authors
  end

  def test_bindir_equals
    @a1.bindir = 'apps'

    assert_equal 'apps', @a1.bindir
  end

  def test_bindir_equals_nil
    @a2.bindir = nil
    @a2.executable = 'app'

    assert_nil                             @a2.bindir
    assert_equal %w[app lib/code.rb].sort, @a2.files
  end

  def test_extensions_equals_nil
    @a2.instance_variable_set(:@extensions, nil)
    assert_nil                    @a2.instance_variable_get(:@extensions)
    assert_equal %w[lib/code.rb], @a2.files
  end

  def test_test_files_equals_nil
    @a2.instance_variable_set(:@test_files, nil)
    assert_nil                    @a2.instance_variable_get(:@test_files)
    assert_equal %w[lib/code.rb], @a2.files
  end

  def test_executables_equals_nil
    @a2.instance_variable_set(:@executables, nil)
    assert_nil                    @a2.instance_variable_get(:@executables)
    assert_equal %w[lib/code.rb], @a2.files
  end

  def test_extra_rdoc_files_equals_nil
    @a2.instance_variable_set(:@extra_rdoc_files, nil)
    assert_nil                    @a2.instance_variable_get(:@extra_rdoc_files)
    assert_equal %w[lib/code.rb], @a2.files
  end

  def test_build_args
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    assert_empty @ext.build_args

    File.open @ext.build_info_file, 'w' do |io|
      io.puts
    end

    assert_empty @ext.build_args

    File.open @ext.build_info_file, 'w' do |io|
      io.puts '--with-foo-dir=wherever'
    end

    assert_equal %w[--with-foo-dir=wherever], @ext.build_args
  end

  def test_build_extensions
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    assert_path_not_exist @ext.extension_dir, 'sanity check'
    refute_empty @ext.extensions, 'sanity check'

    extconf_rb = File.join @ext.gem_dir, @ext.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    @ext.build_extensions

    assert_path_exist @ext.extension_dir
  end

  def test_default_spec_stub_is_marked_default
    default = new_default_spec 'default', 2
    install_default_gems default

    stub = Gem::Specification.stubs.find {|s| s.name == 'default' }
    assert_predicate stub, :default_gem?

    stub = Gem::Specification.find_all_by_name('default').first
    assert_predicate stub, :default_gem?
  end

  def test_build_extensions_built
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    refute_empty @ext.extensions, 'sanity check'

    gem_build_complete =
      File.join @ext.extension_dir, 'gem.build_complete'

    FileUtils.mkdir_p @ext.extension_dir
    FileUtils.touch gem_build_complete

    @ext.build_extensions

    gem_make_out = File.join @ext.extension_dir, 'gem_make.out'
    assert_path_not_exist gem_make_out
  end

  def test_build_extensions_default_gem
    spec = new_default_spec 'default', 1
    spec.extensions << 'extconf.rb'

    extconf_rb = File.join spec.gem_dir, spec.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    spec.build_extensions

    assert_path_not_exist spec.extension_dir
  end

  def test_build_extensions_error
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    refute_empty @ext.extensions, 'sanity check'

    assert_raise Gem::Ext::BuildError do
      @ext.build_extensions
    end
  end

  def test_build_extensions_extensions_dir_unwritable
    pend 'chmod not supported' if Gem.win_platform?
    pend 'skipped in root privilege' if Process.uid.zero?

    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    refute_empty @ext.extensions, 'sanity check'

    extconf_rb = File.join @ext.gem_dir, @ext.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    FileUtils.mkdir_p File.join @ext.base_dir, 'extensions'
    FileUtils.chmod 0555, @ext.base_dir
    FileUtils.chmod 0555, File.join(@ext.base_dir, 'extensions')

    @ext.build_extensions
    assert_path_not_exist @ext.extension_dir
  ensure
    unless ($DEBUG or win_platform? or Process.uid.zero? or Gem.java_platform?)
      FileUtils.chmod 0755, File.join(@ext.base_dir, 'extensions')
      FileUtils.chmod 0755, @ext.base_dir
    end
  end

  def test_build_extensions_no_extensions_dir_unwritable
    pend 'chmod not supported' if Gem.win_platform?
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    refute_empty @ext.extensions, 'sanity check'

    extconf_rb = File.join @ext.gem_dir, @ext.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    FileUtils.rm_r File.join @gemhome, 'extensions'
    FileUtils.chmod 0555, @gemhome

    @ext.build_extensions

    gem_make_out = File.join @ext.extension_dir, 'gem_make.out'
    assert_path_not_exist gem_make_out
  ensure
    FileUtils.chmod 0755, @gemhome
  end

  def test_build_extensions_none
    assert_path_not_exist @a1.extension_dir, 'sanity check'
    assert_empty @a1.extensions, 'sanity check'

    @a1.build_extensions

    assert_path_not_exist @a1.extension_dir
  end

  def test_build_extensions_preview
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    extconf_rb = File.join @ext.gem_dir, @ext.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    refute_empty @ext.extensions, 'sanity check'

    @ext.installed_by_version = v('2.2.0.preview.2')

    @ext.build_extensions

    gem_make_out = File.join @ext.extension_dir, 'gem_make.out'
    assert_path_exist gem_make_out
  end

  def test_contains_requirable_file_eh
    code_rb = File.join @a1.gem_dir, 'lib', 'code.rb'
    FileUtils.mkdir_p File.dirname code_rb
    FileUtils.touch code_rb

    assert @a1.contains_requirable_file? 'code'
  end

  def test_contains_requirable_file_eh_extension
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    _, err = capture_output do
      refute @ext.contains_requirable_file? 'nonexistent'
    end

    expected = "Ignoring ext-1 because its extensions are not built. " +
               "Try: gem pristine ext --version 1\n"

    assert_equal expected, err
  end

  def test_contains_requirable_file_eh_extension_java_platform
    ext_spec(platform: Gem::Platform.new("java"))

    _, err = capture_output do
      refute @ext.contains_requirable_file? 'nonexistent'
    end

    assert_empty err
  end

  def test_date
    assert_date @a1.date
  end

  def test_date_equals_date
    @a1.date = Date.new(2003, 9, 17)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_string
    @a1.date = '2003-09-17'
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_string_bad
    assert_raise Gem::InvalidSpecificationException do
      @a1.date = '9/11/2003'
    end
  end

  def test_date_equals_time
    @a1.date = Time.local(2003, 9, 17, 0,0,0)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_local
    @a1.date = Time.local(2003, 9, 17, 19,50,0) # may not pass in utc >= +4
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_equals_time_utc
    @a1.date = Time.utc(2003, 9, 17, 19,50,0)
    assert_equal Time.utc(2003, 9, 17, 0,0,0), @a1.date
  end

  def test_date_tolerates_hour_sec_zulu
    @a1.date = "2012-01-12 11:22:33.4444444 Z"
    assert_equal Time.utc(2012,01,12,0,0,0), @a1.date
  end

  def test_date_tolerates_hour_sec_and_timezone
    @a1.date = "2012-01-12 11:22:33.4444444 +02:33"
    assert_equal Time.utc(2012,01,12,0,0,0), @a1.date
  end

  def test_date_use_env_source_date_epoch
    epoch = ENV["SOURCE_DATE_EPOCH"]
    ENV["SOURCE_DATE_EPOCH"] = "123456789"
    assert_equal Time.utc(1973,11,29,0,0,0), @a1.date
  ensure
    ENV["SOURCE_DATE_EPOCH"] = epoch
  end

  def test_dependencies
    util_setup_deps
    assert_equal [@bonobo, @monkey], @gem.dependencies
  end

  def test_dependent_gems
    util_setup_deps

    assert_empty @gem.dependent_gems

    bonobo = util_spec 'bonobo', 1
    install_gem bonobo
    install_gem @gem

    expected = [
      [@gem, @bonobo, [bonobo]],
    ]

    assert_equal expected, bonobo.dependent_gems
  end

  def test_doc_dir
    assert_equal File.join(@gemhome, 'doc', 'a-1'), @a1.doc_dir
  end

  def test_doc_dir_type
    assert_equal File.join(@gemhome, 'doc', 'a-1', 'ri'), @a1.doc_dir('ri')
  end

  def test_runtime_dependencies
    util_setup_deps
    assert_equal [@bonobo], @gem.runtime_dependencies
  end

  def test_development_dependencies
    util_setup_deps
    assert_equal [@monkey], @gem.development_dependencies
  end

  def test_description
    assert_equal 'This is a test description', @a1.description
  end

  def test_eql_eh
    g1 = util_spec 'gem', 1
    g2 = util_spec 'gem', 1

    assert_equal g1, g2
    assert_equal g1.hash, g2.hash
    assert_equal true, g1.eql?(g2)
  end

  def test_eql_eh_extensions
    spec = @a1.dup
    spec.extensions = 'xx'

    refute_operator @a1, :eql?, spec
    refute_operator spec, :eql?, @a1
  end

  def test_executables
    @a1.executable = 'app'
    assert_equal %w[app], @a1.executables
  end

  def test_executable_equals
    @a2.executable = 'app'
    assert_equal 'app', @a2.executable
    assert_equal %w[bin/app lib/code.rb].sort, @a2.files
  end

  def test_extensions
    assert_equal ['ext/extconf.rb'], ext_spec.extensions
  end

  def test_extension_dir
    enable_shared, RbConfig::CONFIG['ENABLE_SHARED'] =
      RbConfig::CONFIG['ENABLE_SHARED'], 'no'

    ext_spec

    refute_empty @ext.extensions

    expected =
      File.join(@ext.base_dir, 'extensions', Gem::Platform.local.to_s,
                "#{Gem.ruby_api_version}-static", @ext.full_name)

    assert_equal expected, @ext.extension_dir
  ensure
    RbConfig::CONFIG['ENABLE_SHARED'] = enable_shared
  end

  def test_extension_dir_override
    enable_shared, RbConfig::CONFIG['ENABLE_SHARED'] =
      RbConfig::CONFIG['ENABLE_SHARED'], 'no'

    class << Gem
      alias orig_default_ext_dir_for default_ext_dir_for

      remove_method :default_ext_dir_for

      def Gem.default_ext_dir_for(base_dir)
        'elsewhere'
      end
    end

    ext_spec

    refute_empty @ext.extensions

    expected = File.join @tempdir, 'elsewhere', @ext.full_name

    assert_equal expected, @ext.extension_dir
  ensure
    RbConfig::CONFIG['ENABLE_SHARED'] = enable_shared

    class << Gem
      remove_method :default_ext_dir_for

      alias default_ext_dir_for orig_default_ext_dir_for
    end
  end

  def test_files
    @a1.files = %w[files bin/common]
    @a1.test_files = %w[test_files bin/common]
    @a1.executables = %w[executables common]
    @a1.extra_rdoc_files = %w[extra_rdoc_files bin/common]
    @a1.extensions = %w[extensions bin/common]

    expected = %w[
      bin/common
      bin/executables
      extensions
      extra_rdoc_files
      files
      test_files
    ]
    assert_equal expected, @a1.files
  end

  def test_files_append
    @a1.files            = %w[files bin/common]
    @a1.test_files       = %w[test_files bin/common]
    @a1.executables      = %w[executables common]
    @a1.extra_rdoc_files = %w[extra_rdoc_files bin/common]
    @a1.extensions       = %w[extensions bin/common]

    expected = %w[
      bin/common
      bin/executables
      extensions
      extra_rdoc_files
      files
      test_files
    ]
    assert_equal expected, @a1.files

    @a1.files << "generated_file.c"

    expected << "generated_file.c"
    expected.sort!

    assert_equal expected, @a1.files
  end

  def test_files_duplicate
    @a2.files = %w[a b c d b]
    @a2.extra_rdoc_files = %w[x y z x]
    @a2.normalize

    assert_equal %w[a b c d x y z], @a2.files
    assert_equal %w[x y z], @a2.extra_rdoc_files
  end

  def test_files_extra_rdoc_files
    @a2.files = %w[a b c d]
    @a2.extra_rdoc_files = %w[x y z]
    @a2.normalize
    assert_equal %w[a b c d x y z], @a2.files
  end

  def test_files_non_array
    @a1.files = "F"
    @a1.test_files = "TF"
    @a1.executables = "X"
    @a1.extra_rdoc_files = "ERF"
    @a1.extensions = "E"

    assert_equal %w[E ERF F TF bin/X], @a1.files
  end

  def test_files_non_array_pathological
    @a1.instance_variable_set :@files, "F"
    @a1.instance_variable_set :@test_files, "TF"
    @a1.instance_variable_set :@extra_rdoc_files, "ERF"
    @a1.instance_variable_set :@extensions, "E"
    @a1.instance_variable_set :@executables, "X"

    assert_equal %w[E ERF F TF bin/X], @a1.files
    assert_kind_of Integer, @a1.hash
  end

  def test_for_cache
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'
    @a2.test_files = %w[test/test_b.rb]

    refute_empty @a2.files
    refute_empty @a2.test_files

    spec = @a2.for_cache

    assert_empty spec.files
    assert_empty spec.test_files

    refute_empty @a2.files
    refute_empty @a2.test_files
  end

  def test_full_gem_path
    assert_equal File.join(@gemhome, 'gems', @a1.full_name), @a1.full_gem_path

    @a1.original_platform = 'mswin32'

    assert_equal File.join(@gemhome, 'gems', @a1.original_name),
                 @a1.full_gem_path
  end

  def test_full_gem_path_double_slash
    gemhome = @gemhome.to_s.sub(/\w\//, '\&/')
    @a1.loaded_from = File.join gemhome, "specifications", @a1.spec_name

    expected = File.join @gemhome, "gems", @a1.full_name
    assert_equal expected, @a1.full_gem_path
  end

  def test_full_name
    assert_equal 'a-1', @a1.full_name

    @a1 = Gem::Specification.new "a", 1
    @a1.platform = Gem::Platform.new ['universal', 'darwin', nil]
    assert_equal 'a-1-universal-darwin', @a1.full_name

    @a1 = Gem::Specification.new "a", 1
    @a1.instance_variable_set :@new_platform, 'mswin32'
    assert_equal 'a-1-mswin32', @a1.full_name, 'legacy'

    return if win_platform?

    @a1 = Gem::Specification.new "a", 1
    @a1.platform = 'current'
    assert_equal 'a-1-x86-darwin-8', @a1.full_name
  end

  def test_full_name_windows
    test_cases = {
      'i386-mswin32'      => 'a-1-x86-mswin32-60',
      'i386-mswin32_80'   => 'a-1-x86-mswin32-80',
      'i386-mingw32'      => 'a-1-x86-mingw32',
    }

    test_cases.each do |arch, expected|
      @a1 = Gem::Specification.new "a", 1
      util_set_arch arch
      @a1.platform = 'current'
      assert_equal expected, @a1.full_name
    end
  end

  def test_gem_build_complete_path
    expected = File.join @a1.extension_dir, 'gem.build_complete'
    assert_equal expected, @a1.gem_build_complete_path
  end

  def test_hash
    assert_equal @a1.hash, @a1.hash
    assert_equal @a1.hash, @a1.dup.hash
    refute_equal @a1.hash, @a2.hash
  end

  def test_installed_by_version
    assert_equal v(0), @a1.installed_by_version

    @a1.installed_by_version = Gem.rubygems_version

    assert_equal Gem.rubygems_version, @a1.installed_by_version
  end

  def test_base_dir
    assert_equal @gemhome, @a1.base_dir
  end

  def test_base_dir_not_loaded
    @a1.instance_variable_set :@loaded_from, nil

    assert_equal Gem.dir, @a1.base_dir
  end

  def test_base_dir_default
    default_dir =
      File.join Gem.default_specifications_dir, @a1.spec_name

    @a1.instance_variable_set :@loaded_from, default_dir

    assert_equal Gem.default_dir, @a1.base_dir
  end

  def test_lib_files
    @a1.files = %w[lib/foo.rb Rakefile]

    assert_equal %w[lib/foo.rb], @a1.lib_files
  end

  def test_license
    assert_equal 'MIT', @a1.license
  end

  def test_licenses
    assert_equal ['MIT'], @a1.licenses
  end

  def test_name
    assert_equal 'a', @a1.name
  end

  def test_original_name
    assert_equal 'a-1', @a1.full_name

    @a1.platform = 'i386-linux'
    @a1.instance_variable_set :@original_platform, 'i386-linux'
    assert_equal 'a-1-i386-linux', @a1.original_name
  end

  def test_platform
    assert_equal Gem::Platform::RUBY, @a1.platform
  end

  def test_platform_change_reset_full_name
    orig_full_name = @a1.full_name

    @a1.platform = "universal-unknown"
    refute_equal orig_full_name, @a1.full_name
  end

  def test_platform_change_reset_cache_file
    orig_cache_file = @a1.cache_file

    @a1.platform = "universal-unknown"
    refute_equal orig_cache_file, @a1.cache_file
  end

  def test_platform_equals
    @a1.platform = nil
    assert_equal Gem::Platform::RUBY, @a1.platform

    @a1.platform = Gem::Platform::RUBY
    assert_equal Gem::Platform::RUBY, @a1.platform

    test_cases = {
      'i386-mswin32'    => ['x86', 'mswin32', '60'],
      'i386-mswin32_80' => ['x86', 'mswin32', '80'],
      'i386-mingw32'    => ['x86', 'mingw32', nil ],
      'x86-darwin8'     => ['x86', 'darwin',  '8' ],
    }

    test_cases.each do |arch, expected|
      util_set_arch arch
      @a1.platform = Gem::Platform::CURRENT
      assert_equal Gem::Platform.new(expected), @a1.platform
    end
  end

  def test_platform_equals_current
    @a1.platform = Gem::Platform::CURRENT
    assert_equal Gem::Platform.local, @a1.platform
    assert_equal Gem::Platform.local.to_s, @a1.original_platform
  end

  def test_platform_equals_legacy
    @a1.platform = 'mswin32'
    assert_equal Gem::Platform.new('x86-mswin32'), @a1.platform

    @a1.platform = 'i586-linux'
    assert_equal Gem::Platform.new('x86-linux'), @a1.platform

    @a1.platform = 'powerpc-darwin'
    assert_equal Gem::Platform.new('ppc-darwin'), @a1.platform
  end

  def test_prerelease_spec_adds_required_rubygems_version
    @prerelease = util_spec('tardis', '2.2.0.a')
    refute @prerelease.required_rubygems_version.satisfied_by?(Gem::Version.new('1.3.1'))
    assert @prerelease.required_rubygems_version.satisfied_by?(Gem::Version.new('1.4.0'))
  end

  def test_require_paths
    enable_shared 'no' do
      ext_spec

      @ext.require_paths = 'lib'

      assert_equal [@ext.extension_dir, 'lib'], @ext.require_paths
    end
  end

  def test_require_paths_default_ext_dir_for
    class << Gem
      send :alias_method, :orig_default_ext_dir_for, :default_ext_dir_for

      remove_method :default_ext_dir_for
    end

    def Gem.default_ext_dir_for(base_dir)
      '/foo'
    end

    enable_shared 'no' do
      ext_spec

      @ext.require_paths = 'lib'

      assert_equal [File.expand_path('/foo/ext-1'), 'lib'], @ext.require_paths
    end
  ensure
    class << Gem
      send :remove_method, :default_ext_dir_for
      send :alias_method,  :default_ext_dir_for, :orig_default_ext_dir_for
      send :remove_method, :orig_default_ext_dir_for
    end
  end

  def test_source
    assert_kind_of Gem::Source::Installed, @a1.source
  end

  def test_source_paths
    ext_spec

    @ext.require_paths = %w[lib ext foo]
    @ext.extensions << 'bar/baz'

    expected = %w[
      lib
      ext
      foo
      bar
    ]

    assert_equal expected, @ext.source_paths
  end

  def test_full_require_paths
    ext_spec

    @ext.require_paths = 'lib'

    expected = [
      File.join(@gemhome, 'gems', @ext.original_name, 'lib'),
      @ext.extension_dir,
    ]

    assert_equal expected, @ext.full_require_paths
  end

  def test_to_fullpath
    ext_spec

    @ext.require_paths = 'lib'

    dir = File.join(@gemhome, 'gems', @ext.original_name, 'lib')
    expected_rb = File.join(dir, 'code.rb')
    FileUtils.mkdir_p dir
    FileUtils.touch expected_rb

    dir = @ext.extension_dir
    ext = RbConfig::CONFIG["DLEXT"]
    expected_so = File.join(dir, "ext.#{ext}")
    FileUtils.mkdir_p dir
    FileUtils.touch expected_so

    assert_nil @ext.to_fullpath("code")
    assert_nil @ext.to_fullpath("code.rb")
    assert_nil @ext.to_fullpath("code.#{ext}")

    assert_nil @ext.to_fullpath("ext")
    assert_nil @ext.to_fullpath("ext.rb")
    assert_nil @ext.to_fullpath("ext.#{ext}")

    @ext.activate

    assert_equal expected_rb, @ext.to_fullpath("code")
    assert_equal expected_rb, @ext.to_fullpath("code.rb")
    assert_nil @ext.to_fullpath("code.#{ext}")

    assert_equal expected_so, @ext.to_fullpath("ext")
    assert_nil @ext.to_fullpath("ext.rb")
    assert_equal expected_so, @ext.to_fullpath("ext.#{ext}")

    assert_nil @ext.to_fullpath("notexist")
  end

  def test_fullpath_return_rb_extension_file_when_exist_the_same_name_file
    ext_spec

    @ext.require_paths = 'lib'

    dir = File.join(@gemhome, 'gems', @ext.original_name, 'lib')
    expected_rb = File.join(dir, 'code.rb')
    FileUtils.mkdir_p dir
    FileUtils.touch expected_rb

    dir = @ext.extension_dir
    ext = RbConfig::CONFIG["DLEXT"]
    expected_so = File.join(dir, "code.#{ext}")
    FileUtils.mkdir_p dir
    FileUtils.touch expected_so

    @ext.activate

    assert_equal expected_rb, @ext.to_fullpath("code")
  end

  def test_require_already_activated
    a1 = util_spec "a", "1", nil, "lib/d#{$$}.rb"

    install_specs a1 # , a2, b1, b2, c1, c2

    a1.activate
    assert_equal %w[a-1], loaded_spec_names
    assert_equal [], unresolved_names

    assert require "d#{$$}"

    assert_equal %w[a-1], loaded_spec_names
    assert_equal [], unresolved_names
  end

  def test_require_already_activated_indirect_conflict
    a1 = util_spec "a", "1", "b" => "> 0"
    a2 = util_spec "a", "2", "b" => "> 0"
    b1 = util_spec "b", "1", "c" => ">= 1"
    b2 = util_spec "b", "2", "c" => ">= 2"
    c1 = util_spec "c", "1", nil, "lib/d#{$$}.rb"
    c2 = util_spec("c", "2", { "a" => "1" }, "lib/d#{$$}.rb") # conflicts with a-2

    install_specs c1, b1, a1, a2, c2, b2

    a1.activate
    c1.activate
    assert_equal %w[a-1 c-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names

    assert require "d#{$$}"

    assert_equal %w[a-1 c-1], loaded_spec_names
    assert_equal ["b (> 0)"], unresolved_names
  end

  def test_requirements
    assert_equal ['A working computer'], @a1.requirements
  end

  def test_allowed_push_host
    assert_nil                                   @a1.metadata['allowed_push_host']
    assert_equal 'https://privategemserver.com', @a3.metadata['allowed_push_host']
  end

  def test_runtime_dependencies_legacy
    make_spec_c1
    # legacy gems don't have a type
    @c1.runtime_dependencies.each do |dep|
      dep.instance_variable_set :@type, nil
    end

    expected = %w[rake jabber4r pqa]

    assert_equal expected, @c1.runtime_dependencies.map {|d| d.name }
  end

  def test_spaceship_name
    s1 = util_spec 'a', '1'
    s2 = util_spec 'b', '1'

    assert_equal(-1, (s1 <=> s2))
    assert_equal(0, (s1 <=> s1))
    assert_equal(1, (s2 <=> s1))
  end

  def test_spaceship_platform
    s1 = util_spec 'a', '1'
    s2 = util_spec 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    assert_equal(-1, (s1 <=> s2))
    assert_equal(0, (s1 <=> s1))
    assert_equal(1, (s2 <=> s1))
  end

  def test_spaceship_version
    s1 = util_spec 'a', '1'
    s2 = util_spec 'a', '2'

    assert_equal(-1, (s1 <=> s2))
    assert_equal(0, (s1 <=> s1))
    assert_equal(1, (s2 <=> s1))
  end

  def test_spec_file
    assert_equal File.join(@gemhome, 'specifications', 'a-1.gemspec'),
                 @a1.spec_file
  end

  def test_spec_name
    assert_equal 'a-1.gemspec', @a1.spec_name
  end

  def test_summary
    assert_equal 'this is a summary', @a1.summary
  end

  def test_test_files
    @a1.test_file = 'test/suite.rb'
    assert_equal ['test/suite.rb'], @a1.test_files
  end

  def test_runtime_predicate_true
    @a2.add_runtime_dependency 'b', '1'
    assert_predicate @a2.dependencies.first, :runtime?

    @a2.dependencies.first.instance_variable_set :@type, nil
    assert_predicate @a2.dependencies.first, :runtime?
  end

  def test_runtime_predicate_false
    @a2.add_development_dependency 'b', '1'
    refute_predicate @a2.dependencies.first, :runtime?
  end

  def test_to_ruby
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'
    @a2.require_paths << 'other'

    ruby_code = @a2.to_ruby

    expected = <<-SPEC
# -*- encoding: utf-8 -*-
# stub: a 2 ruby lib\0other

Gem::Specification.new do |s|
  s.name = "a".freeze
  s.version = "2"

  s.required_rubygems_version = Gem::Requirement.new(\"> 0\".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze, "other".freeze]
  s.authors = ["A User".freeze]
  s.date = "#{@a2.date.strftime("%Y-%m-%d")}"
  s.description = "This is a test description".freeze
  s.email = "example@example.com".freeze
  s.files = ["lib/code.rb".freeze]
  s.homepage = "http://example.com".freeze
  s.rubygems_version = "#{Gem::VERSION}".freeze
  s.summary = "this is a summary".freeze

  if s.respond_to? :specification_version then
    s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION}
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<b>.freeze, [\"= 1\"])
  else
    s.add_dependency(%q<b>.freeze, [\"= 1\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @a2, same_spec
  end

  def test_to_ruby_with_rsa_key
    require 'rubygems/openssl'
    pend 'openssl is missing' unless defined?(OpenSSL::PKey::RSA)

    rsa_key = OpenSSL::PKey::RSA.new(2048)
    @a2.signing_key = rsa_key
    ruby_code = @a2.to_ruby

    expected = <<-SPEC
# -*- encoding: utf-8 -*-
# stub: a 2 ruby lib

Gem::Specification.new do |s|
  s.name = "a".freeze
  s.version = "2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["A User".freeze]
  s.date = "#{@a2.date.strftime("%Y-%m-%d")}"
  s.description = "This is a test description".freeze
  s.email = "example@example.com".freeze
  s.files = ["lib/code.rb".freeze]
  s.homepage = "http://example.com".freeze
  s.rubygems_version = "#{Gem::VERSION}".freeze
  s.summary = "this is a summary".freeze
end
    SPEC

    assert_equal expected, ruby_code
  end

  def test_to_ruby_for_cache
    @a2.add_runtime_dependency 'b', '1'
    @a2.dependencies.first.instance_variable_set :@type, nil
    @a2.required_rubygems_version = Gem::Requirement.new '> 0'
    @a2.installed_by_version = Gem.rubygems_version

    # cached specs do not have spec.files populated:
    ruby_code = @a2.to_ruby_for_cache

    expected = <<-SPEC
# -*- encoding: utf-8 -*-
# stub: a 2 ruby lib

Gem::Specification.new do |s|
  s.name = "a".freeze
  s.version = "2"

  s.required_rubygems_version = Gem::Requirement.new(\"> 0\".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["A User".freeze]
  s.date = "#{@a2.date.strftime("%Y-%m-%d")}"
  s.description = "This is a test description".freeze
  s.email = "example@example.com".freeze
  s.homepage = "http://example.com".freeze
  s.rubygems_version = "#{Gem::VERSION}".freeze
  s.summary = "this is a summary".freeze

  s.installed_by_version = "#{Gem::VERSION}" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = #{Gem::Specification::CURRENT_SPECIFICATION_VERSION}
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<b>.freeze, [\"= 1\"])
  else
    s.add_dependency(%q<b>.freeze, [\"= 1\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    # cached specs do not have spec.files populated:
    @a2.files = []
    assert_equal @a2, same_spec
  end

  def test_to_ruby_fancy
    make_spec_c1

    @c1.platform = Gem::Platform.local
    ruby_code = @c1.to_ruby

    local = Gem::Platform.local
    expected_platform = "[#{local.cpu.inspect}, #{local.os.inspect}, #{local.version.inspect}]"
    stub_require_paths =
      @c1.instance_variable_get(:@require_paths).join "\u0000"
    extensions = @c1.extensions.join "\u0000"

    expected = <<-SPEC
# -*- encoding: utf-8 -*-
# stub: a 1 #{win_platform? ? "x86-mswin32-60" : "x86-darwin-8"} #{stub_require_paths}
# stub: #{extensions}

Gem::Specification.new do |s|
  s.name = "a".freeze
  s.version = "1"
  s.platform = Gem::Platform.new(#{expected_platform})

  s.required_rubygems_version = Gem::Requirement.new(\">= 0\".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["A User".freeze]
  s.date = "#{@c1.date.strftime("%Y-%m-%d")}"
  s.description = "This is a test description".freeze
  s.email = "example@example.com".freeze
  s.executables = ["exec".freeze]
  s.extensions = ["ext/a/extconf.rb".freeze]
  s.files = ["bin/exec".freeze, "ext/a/extconf.rb".freeze, "lib/code.rb".freeze, "test/suite.rb".freeze]
  s.homepage = "http://example.com".freeze
  s.licenses = ["MIT".freeze]
  s.requirements = ["A working computer".freeze]
  s.rubygems_version = "#{Gem::VERSION}".freeze
  s.summary = "this is a summary".freeze
  s.test_files = ["test/suite.rb".freeze]

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<rake>.freeze, [\"> 0.4\"])
    s.add_runtime_dependency(%q<jabber4r>.freeze, [\"> 0.0.0\"])
    s.add_runtime_dependency(%q<pqa>.freeze, [\"> 0.4\", \"<= 0.6\"])
  else
    s.add_dependency(%q<rake>.freeze, [\"> 0.4\"])
    s.add_dependency(%q<jabber4r>.freeze, [\"> 0.0.0\"])
    s.add_dependency(%q<pqa>.freeze, [\"> 0.4\", \"<= 0.6\"])
  end
end
    SPEC

    assert_equal expected, ruby_code

    same_spec = eval ruby_code

    assert_equal @c1, same_spec
  end

  def test_to_ruby_keeps_requirements_as_originally_specified
    spec = util_spec 'a', '1' do |s|
      s.add_dependency 'b', ['~> 1.0', '>= 1.0.0']
    end

    assert_includes spec.to_ruby, '"~> 1.0", ">= 1.0.0"'
  end

  def test_to_ruby_legacy
    gemspec1 = Gem::Deprecate.skip_during do
      eval LEGACY_RUBY_SPEC
    end
    ruby_code = gemspec1.to_ruby
    gemspec2 = eval ruby_code

    assert_equal gemspec1, gemspec2
  end

  def test_to_ruby_nested_hash
    metadata = {}
    metadata[metadata] = metadata

    @a2.metadata = metadata

    ruby = @a2.to_ruby

    assert_match %r%^  s\.metadata = \{ "%, ruby
  end

  def test_to_ruby_platform
    @a2.platform = Gem::Platform.local
    @a2.instance_variable_set :@original_platform, 'old_platform'

    ruby_code = @a2.to_ruby

    same_spec = eval ruby_code

    assert_equal 'old_platform', same_spec.original_platform
  end

  def test_to_yaml
    yaml_str = @a1.to_yaml

    refute_match %r{!!null}, yaml_str

    same_spec = Gem::Specification.from_yaml(yaml_str)

    assert_equal @a1, same_spec
  end

  def test_to_yaml_fancy
    @a1.platform = Gem::Platform.local
    yaml_str = @a1.to_yaml

    same_spec = Gem::Specification.from_yaml(yaml_str)

    assert_equal Gem::Platform.local, same_spec.platform

    assert_equal @a1, same_spec
  end

  def test_to_yaml_platform_empty_string
    @a1.instance_variable_set :@original_platform, ''

    assert_match %r{^platform: ruby$}, @a1.to_yaml
  end

  def test_to_yaml_platform_legacy
    @a1.platform = 'powerpc-darwin7.9.0'
    @a1.instance_variable_set :@original_platform, 'powerpc-darwin7.9.0'

    yaml_str = @a1.to_yaml

    same_spec = load_yaml yaml_str

    assert_equal Gem::Platform.new('powerpc-darwin7'), same_spec.platform
    assert_equal 'powerpc-darwin7.9.0', same_spec.original_platform
  end

  def test_to_yaml_platform_nil
    @a1.instance_variable_set :@original_platform, nil

    assert_match %r{^platform: ruby$}, @a1.to_yaml
  end

  def test_validate
    util_setup_validate

    Dir.chdir @tempdir do
      assert @a1.validate
    end
  end

  def x(s); s.gsub(/xxx/, ''); end
  def w; x "WARxxxNING"; end
  def t; x "TOxxxDO"; end
  def f; x "FxxxIXME"; end

  def test_validate_authors
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.authors = [""]

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  no author specified\n", @ui.error, 'error'

      @a1.authors = [Object.new]

      assert_equal [], @a1.authors

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal "authors may not be empty", e.message

      @a1.authors = ["#{f} (who is writing this software)"]

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not an author), e.message

      @a1.authors = ["#{t} (who is writing this software)"]

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not an author), e.message
    end
  end

  def test_validate_autorequire
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.autorequire = 'code'

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  deprecated autorequire specified\n",
                   @ui.error, 'error'
    end
  end

  def test_validate_dependencies
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.add_runtime_dependency     'b', '>= 1.0.rc1'
      @a1.add_development_dependency 'c', '>= 2.0.rc2'
      @a1.add_runtime_dependency     'd', '~> 1.2.3'
      @a1.add_runtime_dependency     'e', '~> 1.2.3.4'
      @a1.add_runtime_dependency     'g', '~> 1.2.3', '>= 1.2.3.4'
      @a1.add_runtime_dependency     'h', '>= 1.2.3', '<= 2'
      @a1.add_runtime_dependency     'i', '>= 1.2'
      @a1.add_runtime_dependency     'j', '>= 1.2.3'
      @a1.add_runtime_dependency     'k', '> 1.2'
      @a1.add_runtime_dependency     'l', '> 1.2.3'
      @a1.add_runtime_dependency     'm', '~> 2.1.0'
      @a1.add_runtime_dependency     'n', '~> 0.1.0'
      @a1.add_runtime_dependency     'o'

      use_ui @ui do
        @a1.validate
      end

      expected = <<-EXPECTED
#{w}:  prerelease dependency on b (>= 1.0.rc1) is not recommended
#{w}:  prerelease dependency on c (>= 2.0.rc2, development) is not recommended
#{w}:  open-ended dependency on i (>= 1.2) is not recommended
  if i is semantically versioned, use:
    add_runtime_dependency 'i', '~> 1.2'
#{w}:  open-ended dependency on j (>= 1.2.3) is not recommended
  if j is semantically versioned, use:
    add_runtime_dependency 'j', '~> 1.2', '>= 1.2.3'
#{w}:  open-ended dependency on k (> 1.2) is not recommended
  if k is semantically versioned, use:
    add_runtime_dependency 'k', '~> 1.2', '> 1.2'
#{w}:  open-ended dependency on l (> 1.2.3) is not recommended
  if l is semantically versioned, use:
    add_runtime_dependency 'l', '~> 1.2', '> 1.2.3'
#{w}:  open-ended dependency on o (>= 0) is not recommended
  use a bounded requirement, such as '~> x.y'
#{w}:  See https://guides.rubygems.org/specification-reference/ for help
      EXPECTED

      assert_equal expected, @ui.error, 'warning'
    end
  end

  def test_validate_dependencies_duplicates
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.add_runtime_dependency 'b', '~> 1.2'
      @a1.add_runtime_dependency 'b', '>= 1.2.3'
      @a1.add_development_dependency 'c', '~> 1.2'
      @a1.add_development_dependency 'c', '>= 1.2.3'

      use_ui @ui do
        e = assert_raise Gem::InvalidSpecificationException do
          @a1.validate
        end

        expected = <<-EXPECTED
duplicate dependency on b (>= 1.2.3), (~> 1.2) use:
    add_runtime_dependency 'b', '>= 1.2.3', '~> 1.2'
duplicate dependency on c (>= 1.2.3, development), (~> 1.2) use:
    add_development_dependency 'c', '>= 1.2.3', '~> 1.2'
        EXPECTED

        assert_equal expected, e.message
      end

      assert_equal <<-EXPECTED, @ui.error
#{w}:  See https://guides.rubygems.org/specification-reference/ for help
      EXPECTED
    end
  end

  def test_validate_dependencies_allowed_duplicates
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.add_runtime_dependency 'b', '~> 1.2'
      @a1.add_development_dependency 'b', '= 1.2.3'

      use_ui @ui do
        @a1.validate
      end

      assert_equal '', @ui.error, 'warning'
    end
  end

  def test_validate_prerelease_dependencies_with_prerelease_version
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.version = '1.0.0.beta.1'
      @a1.add_runtime_dependency 'b', '~> 1.2.0.beta.1'

      use_ui @ui do
        @a1.validate
      end

      assert_equal '', @ui.error, 'warning'
    end
  end

  def test_validate_rake_extension_have_rake_dependency_warning
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.extensions = ['Rakefile']
      File.write File.join(@tempdir, 'Rakefile'), ''

      use_ui @ui do
        @a1.validate
      end

      assert_match(/add rake as a dependency/, @ui.error)
    end
  end

  def test_validate_rake_extension_have_rake_dependency_no_warning
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.extensions = ['Rakefile']
      @a1.add_runtime_dependency 'rake'
      File.write File.join(@tempdir, 'Rakefile'), ''

      use_ui @ui do
        @a1.validate
      end

      refute_match(/add rake as a dependency/, @ui.error)
    end
  end

  def test_validate_description
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.description = ''

      use_ui @ui do
        @a1.validate
      end

      @ui = Gem::MockGemUi.new
      @a1.summary = "this is my summary"
      @a1.description = @a1.summary

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  description and summary are identical\n",
                   @ui.error, "error"

      @a1.description = "#{f} (describe your package)"

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not a description), e.message

      @a1.description = "#{t} (describe your package)"

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not a description), e.message

      # Adding #{f} anywhere after the start of the description should be fine.
      @a1.description = "(some description) #{f}"

      assert_nothing_raised do
        @a1.validate
      end

      # Adding #{t} anywhere after the start of the description should be fine.
      @a1.description = "(some description) #{t}"

      assert_nothing_raised do
        @a1.validate
      end

      # Adding #{f} at the start of the second or later line should be fine.
      @a1.description = "(some description)\n#{f}"

      assert_nothing_raised do
        @a1.validate
      end

      # Adding #{t} at the start of the second or later line should be fine.
      @a1.description = "(some description)\n#{t}"

      assert_nothing_raised do
        @a1.validate
      end
    end
  end

  def test_validate_email
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.email = "FIxxxXME (your e-mail)".sub(/xxx/, "")

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not an email), e.message

      @a1.email = "#{t} (your e-mail)"

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not an email), e.message
    end
  end

  def test_validate_empty
    e = assert_raise Gem::InvalidSpecificationException do
      Gem::Specification.new.validate
    end

    assert_equal 'missing value for attribute name', e.message
  end

  def test_validate_error
    assert_raise Gem::InvalidSpecificationException do
      use_ui @ui do
        Gem::Specification.new.validate
      end
    end

    assert_match 'See https://guides.rubygems.org/specification-reference/ for help', @ui.error
  end

  def test_validate_executables
    util_setup_validate

    FileUtils.mkdir_p File.join(@tempdir, 'bin')
    File.write File.join(@tempdir, 'bin', 'exec'), ''
    FileUtils.mkdir_p File.join(@tempdir, 'exec')

    use_ui @ui do
      Dir.chdir @tempdir do
        assert @a1.validate
      end
    end

    assert_equal %w[exec], @a1.executables

    assert_equal '', @ui.output, 'output'
    assert_match "#{w}:  bin/exec is missing #! line\n", @ui.error, 'error'
  end

  def test_validate_empty_require_paths
    if win_platform?
      pend 'test_validate_empty_require_paths skipped on MS Windows (symlink)'
    else
      util_setup_validate

      @a1.require_paths = []
      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal 'specification must have at least one require_path',
                   e.message
    end
  end

  def test_validate_files
    pend 'test_validate_files skipped on MS Windows (symlink)' if win_platform?
    util_setup_validate

    @a1.files += ['lib', 'lib2']
    @a1.extensions << 'ext/a/extconf.rb'

    Dir.chdir @tempdir do
      FileUtils.ln_s 'lib/code.rb', 'lib2' unless vc_windows?

      use_ui @ui do
        @a1.validate
      end

      assert_match 'WARNING:  lib2 is a symlink, which is not supported on all platforms', @ui.error
    end

    assert_equal %w[bin/exec ext/a/extconf.rb lib/code.rb lib2 test/suite.rb].sort,
                 @a1.files
  end

  def test_unresolved_specs
    specification = Gem::Specification.clone

    set_orig specification

    specification.define_singleton_method(:unresolved_deps) do
      { b: Gem::Dependency.new("x","1") }
    end

    specification.define_singleton_method(:find_all_by_name) do |dep_name|
      []
    end

    expected = <<-EXPECTED
WARN: Unresolved or ambiguous specs during Gem::Specification.reset:
      x (= 1)
WARN: Clearing out unresolved specs. Try 'gem cleanup <gem>'
Please report a bug if this causes problems.
    EXPECTED

    actual_stdout, actual_stderr = capture_output do
      specification.reset
    end
    assert_empty actual_stdout
    assert_equal(expected, actual_stderr)
  end

  def test_unresolved_specs_with_versions
    specification = Gem::Specification.clone

    set_orig specification

    specification.define_singleton_method(:unresolved_deps) do
      { b: Gem::Dependency.new("x","1") }
    end

    specification.define_singleton_method(:find_all_by_name) do |dep_name|
      [
        specification.new {|s| s.name = "z", s.version = Gem::Version.new("1") },
        specification.new {|s| s.name = "z", s.version = Gem::Version.new("2") },
      ]
    end

    expected = <<-EXPECTED
WARN: Unresolved or ambiguous specs during Gem::Specification.reset:
      x (= 1)
      Available/installed versions of this gem:
      - 1
      - 2
WARN: Clearing out unresolved specs. Try 'gem cleanup <gem>'
Please report a bug if this causes problems.
    EXPECTED

    actual_stdout, actual_stderr = capture_output do
      specification.reset
    end
    assert_empty actual_stdout
    assert_equal(expected, actual_stderr)
  end

  def test_duplicate_runtime_dependency
    expected = "WARNING: duplicated b dependency [\"~> 3.0\", \"~> 3.0\"]\n"
    out, err = capture_output do
      @a1.add_runtime_dependency "b", "~> 3.0", "~> 3.0"
    end
    assert_empty out
    assert_equal(expected, err)
  end

  def set_orig(cls)
    s_cls = cls.singleton_class
    s_cls.send :alias_method, :orig_unresolved_deps , :unresolved_deps
    s_cls.send :alias_method, :orig_find_all_by_name, :find_all_by_name
  end

  def test_validate_files_recursive
    util_setup_validate
    FileUtils.touch @a1.file_name

    @a1.files = [@a1.file_name]

    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end

    assert_equal "#{@a1.full_name} contains itself (#{@a1.file_name}), check your files list",
                 e.message
  end

  def test_validate_homepage
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.homepage = nil

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  no homepage specified\n", @ui.error, 'error'

      @ui = Gem::MockGemUi.new

      @a1.homepage = ''

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  no homepage specified\n", @ui.error, 'error'

      @a1.homepage = 'over at my cool site'

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal '"over at my cool site" is not a valid HTTP URI', e.message

      @a1.homepage = 'ftp://rubygems.org'

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal '"ftp://rubygems.org" is not a valid HTTP URI', e.message

      @a1.homepage = 'https://rubygems.org/'
      assert_equal true, @a1.validate

      @a1.homepage = 'https://rubygems.org'
      assert_equal true, @a1.validate

    end
  end

  def test_validate_license
    util_setup_validate

    use_ui @ui do
      @a1.licenses.clear
      @a1.validate
    end

    assert_match <<-WARNING, @ui.error
WARNING:  licenses is empty, but is recommended.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
    WARNING
  end

  def test_validate_license_in_a_non_packaging_context
    util_setup_validate

    use_ui @ui do
      @a1.licenses.clear
      @a1.validate(false)
    end

    assert_empty @ui.error
  end

  def test_removed_methods
    assert_equal Gem::Specification::REMOVED_METHODS, [:rubyforge_project=]
  end

  def test_validate_removed_rubyforge_project
    util_setup_validate

    use_ui @ui do
      @a1.rubyforge_project = 'invalid-attribute'
      @a1.validate
    end

    assert_match "rubyforge_project= is deprecated", @ui.error
  end

  def test_validate_license_values
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['BSD']
      @a1.validate
    end

    assert_match <<-WARNING, @ui.error
WARNING:  license value 'BSD' is invalid.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
    WARNING
  end

  def test_validate_license_ref
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['LicenseRef-LICENSE.md']
      @a1.validate
    end

    assert_empty @ui.error
  end

  def test_validate_license_values_plus
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['GPL-2.0+']
      @a1.validate
    end

    assert_empty @ui.error
  end

  def test_validate_license_values_or_later
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['GPL-2.0-or-later']
      @a1.validate
    end

    assert_empty @ui.error
  end

  def test_validate_license_values_with
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['GPL-2.0+ WITH Autoconf-exception-2.0']
      @a1.validate
    end

    assert_empty @ui.error
  end

  def test_validate_license_with_nonsense_suffix
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['GPL-2.0+ FOO', 'GPL-2.0 FOO']
      @a1.validate
    end

    assert_match <<-WARNING, @ui.error
WARNING:  license value 'GPL-2.0+ FOO' is invalid.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
    WARNING
    assert_match <<-WARNING, @ui.error
WARNING:  license value 'GPL-2.0 FOO' is invalid.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
    WARNING
  end

  def test_validate_license_with_invalid_exception
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['GPL-2.0+ WITH Autocofn-exception-2.0']
      @a1.validate
    end

    assert_match <<-WARNING, @ui.error
WARNING:  license value 'GPL-2.0+ WITH Autocofn-exception-2.0' is invalid.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
    WARNING
  end

  def test_validate_license_gives_suggestions
    util_setup_validate

    use_ui @ui do
      @a1.licenses = ['ruby']
      @a1.validate
    end

    assert_match <<-WARNING, @ui.error
WARNING:  license value 'ruby' is invalid.  Use a license identifier from
http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.
Did you mean 'Ruby'?
    WARNING
  end

  def test_validate_empty_files
    util_setup_validate

    use_ui @ui do
      # we have to set all of these for #files to be empty
      @a1.files = []
      @a1.test_files = []
      @a1.executables = []

      @a1.validate
    end

    assert_match "no files specified", @ui.error
  end

  def test_validate_empty_homepage
    util_setup_validate

    use_ui @ui do
      @a1.homepage = nil
      @a1.validate
    end

    assert_match "no homepage specified", @ui.error
  end

  def test_validate_empty_summary
    util_setup_validate

    use_ui @ui do
      @a1.summary = nil
      @a1.validate
    end

    assert_match "no summary specified", @ui.error
  end

  def test_validate_name
    util_setup_validate

    e = assert_raise Gem::InvalidSpecificationException do
      @a1.name = :json
      @a1.validate
    end

    assert_equal 'invalid value for attribute name: ":json" must be a string', e.message

    @a1.name = []
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end
    assert_equal "invalid value for attribute name: \"[]\" must be a string", e.message

    @a1.name = ""
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end
    assert_equal "invalid value for attribute name: \"\" must include at least one letter", e.message

    @a1.name = "12345"
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end
    assert_equal "invalid value for attribute name: \"12345\" must include at least one letter", e.message

    @a1.name = "../malicious"
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end
    assert_equal "invalid value for attribute name: \"../malicious\" can only include letters, numbers, dashes, and underscores", e.message

    @a1.name = "\ba\t"
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end
    assert_equal "invalid value for attribute name: \"\\ba\\t\" can only include letters, numbers, dashes, and underscores", e.message
  end

  def test_validate_non_nil
    util_setup_validate

    Dir.chdir @tempdir do
      assert @a1.validate

      Gem::Specification.non_nil_attributes.each do |name|
        next if name == :files # set by #normalize
        spec = @a1.dup
        spec.instance_variable_set "@#{name}", nil

        e = assert_raise Gem::InvalidSpecificationException do
          spec.validate
        end

        assert_match %r{^#{name}}, e.message
      end
    end
  end

  def test_validate_permissions
    pend 'chmod not supported' if Gem.win_platform?

    util_setup_validate

    Dir.chdir @tempdir do
      File.chmod 0640, File.join('lib', 'code.rb')
      File.chmod 0640, File.join('bin', 'exec')

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  lib/code.rb is not world-readable\n", @ui.error
      assert_match "#{w}:  bin/exec is not world-readable\n", @ui.error
      assert_match "#{w}:  bin/exec is not executable\n", @ui.error
    end
  end

  def test_validate_permissions_of_missing_file_non_packaging
    pend 'chmod not supported' if Gem.win_platform?

    util_setup_validate

    Dir.chdir @tempdir do
      File.delete File.join('lib', 'code.rb')

      use_ui @ui do
        assert @a1.validate(false)
      end
    end
  end

  def test_validate_platform_legacy
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.platform = 'mswin32'
      assert @a1.validate

      @a1.platform = 'i586-linux'
      assert @a1.validate

      @a1.platform = 'powerpc-darwin'
      assert @a1.validate
    end
  end

  def test_validate_rubygems_version
    util_setup_validate

    @a1.rubygems_version = "3"
    e = assert_raise Gem::InvalidSpecificationException do
      @a1.validate
    end

    assert_equal "expected RubyGems version #{Gem::VERSION}, was 3",
                 e.message
  end

  def test_validate_specification_version
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.specification_version = '1.0'

      e = assert_raise Gem::InvalidSpecificationException do
        use_ui @ui do
          @a1.validate
        end
      end

      err = 'specification_version must be an Integer (did you mean version?)'
      assert_equal err, e.message
    end
  end

  def test_validate_summary
    util_setup_validate

    Dir.chdir @tempdir do
      @a1.summary = ''

      use_ui @ui do
        @a1.validate
      end

      assert_match "#{w}:  no summary specified\n", @ui.error, 'error'

      @a1.summary = "#{f} (describe your package)"

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not a summary), e.message

      @a1.summary = "#{t} (describe your package)"

      e = assert_raise Gem::InvalidSpecificationException do
        @a1.validate
      end

      assert_equal %("#{f}" or "#{t}" is not a summary), e.message
    end
  end

  def test_validate_warning
    util_setup_validate

    use_ui @ui do
      @a1.licenses.clear
      @a1.validate
    end

    assert_match 'See https://guides.rubygems.org/specification-reference/ for help', @ui.error
  end

  def test_version
    assert_equal Gem::Version.new('1'), @a1.version
  end

  def test_version_change_reset_full_name
    orig_full_name = @a1.full_name

    @a1.version = "2"

    refute_equal orig_full_name, @a1.full_name
  end

  def test_version_change_reset_cache_file
    orig_cache_file = @a1.cache_file

    @a1.version = "2"

    refute_equal orig_cache_file, @a1.cache_file
  end

  def test__load_fixes_Date_objects
    spec = util_spec "a", 1
    spec.instance_variable_set :@date, Date.today

    spec = Marshal.load Marshal.dump(spec)

    assert_kind_of Time, spec.date
  end

  def test_load_errors_contain_filename
    specfile = Tempfile.new(self.class.name.downcase)
    specfile.write "raise 'boom'"
    specfile.close
    begin
      capture_output do
        Gem::Specification.load(specfile.path)
      end
    rescue => e
      name_rexp = Regexp.new(Regexp.escape(specfile.path))
      assert e.backtrace.grep(name_rexp).any?
    end
  ensure
    specfile.delete
  end

  def test_latest_specs
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1 do |s|
        s.platform = Gem::Platform.new 'x86-my_platform1'
      end

      fetcher.spec 'a', 2

      fetcher.spec 'a', 2 do |s|
        s.platform = Gem::Platform.new 'x86-my_platform1'
      end

      fetcher.spec 'a', 2 do |s|
        s.platform = Gem::Platform.new 'x86-other_platform1'
      end

      fetcher.spec 'a', 3 do |s|
        s.platform = Gem::Platform.new 'x86-other_platform1'
      end
    end

    expected = %W[
      a-3-x86-other_platform-1
    ]

    latest_specs = Gem::Specification.latest_specs.map(&:full_name).sort

    assert_equal expected, latest_specs
  end

  def test_metadata_validates_ok
    util_setup_validate

    Dir.chdir @tempdir do
      @m1 = quick_gem 'm', '1' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = {
          "one"          => "two",
          "home"         => "three",
          "homepage_uri" => "https://example.com/user/repo",
          "funding_uri"  => "https://example.com/donate",
        }
      end

      use_ui @ui do
        @m1.validate
      end
    end
  end

  def test_metadata_key_type_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 1 => "fail" }
      end

      e = assert_raise Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata keys must be a String", e.message
    end
  end

  def test_metadata_key_size_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { ("x" * 129) => "fail" }
      end

      e = assert_raise Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata key is too large (129 > 128)", e.message
    end
  end

  def test_metadata_value_type_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'fail' => [] }
      end

      e = assert_raise Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata['fail'] value must be a String", e.message
    end
  end

  def test_metadata_value_size_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'fail' => ("x" * 1025) }
      end

      e = assert_raise Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata['fail'] value is too large (1025 > 1024)", e.message
    end
  end

  def test_metadata_link_validation_fails
    util_setup_validate

    Dir.chdir @tempdir do
      @m2 = quick_gem 'm', '2' do |s|
        s.files = %w[lib/code.rb]
        s.metadata = { 'homepage_uri' => 'http:/example.com' }
      end

      e = assert_raise Gem::InvalidSpecificationException do
        @m2.validate
      end

      assert_equal "metadata['homepage_uri'] has invalid link: \"http:/example.com\"", e.message
    end
  end

  def test_metadata_specs
    @m1 = quick_gem 'm', '1' do |s|
      s.files = %w[lib/code.rb]
      s.metadata = { 'one' => "two", 'two' => "three" }
    end

    valid_ruby_spec = <<-EOF
# -*- encoding: utf-8 -*-
# stub: m 1 ruby lib

Gem::Specification.new do |s|
  s.name = "m".freeze
  s.version = "1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "one" => "two", "two" => "three" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["A User".freeze]
  s.date = "#{@m1.date.strftime("%Y-%m-%d")}"
  s.description = "This is a test description".freeze
  s.email = "example@example.com".freeze
  s.files = ["lib/code.rb".freeze]
  s.homepage = "http://example.com".freeze
  s.rubygems_version = "#{Gem::VERSION}".freeze
  s.summary = "this is a summary".freeze
end
    EOF

    assert_equal @m1.to_ruby, valid_ruby_spec
  end

  def test_missing_extensions_eh
    pend "extensions don't quite work on jruby" if Gem.java_platform?
    ext_spec

    assert @ext.missing_extensions?

    extconf_rb = File.join @ext.gem_dir, @ext.extensions.first
    FileUtils.mkdir_p File.dirname extconf_rb

    File.open extconf_rb, 'w' do |f|
      f.write <<-'RUBY'
        File.open 'Makefile', 'w' do |f|
          f.puts "clean:\n\techo clean"
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    @ext.build_extensions

    refute @ext.missing_extensions?
  end

  def test_missing_extensions_eh_default_gem
    spec = new_default_spec 'default', 1
    spec.extensions << 'extconf.rb'

    refute spec.missing_extensions?
  end

  def test_missing_extensions_eh_none
    refute @a1.missing_extensions?
  end

  def test_find_all_by_full_name
    pl = Gem::Platform.new 'i386-linux'

    a1 = util_spec "a", "1"
    a1_pre = util_spec "a", "1.0.0.pre.1"
    a_1_platform = util_spec("a", "1") {|s| s.platform = pl }
    a_b_1 = util_spec "a-b", "1"
    a_b_1_platform = util_spec("a-b", "1") {|s| s.platform = pl }

    a_b_1_1 = util_spec "a-b-1", "1"
    a_b_1_1_platform = util_spec("a-b-1", "1") {|s| s.platform = pl }

    install_specs(a1, a1_pre, a_1_platform, a_b_1, a_b_1_platform,
                  a_b_1_1, a_b_1_1_platform)

    assert_equal [a1], Gem::Specification.find_all_by_full_name("a-1")
    assert_equal [a1_pre], Gem::Specification.find_all_by_full_name("a-1.0.0.pre.1")
    assert_equal [a_1_platform], Gem::Specification.find_all_by_full_name("a-1-x86-linux")
    assert_equal [a_b_1_1], Gem::Specification.find_all_by_full_name("a-b-1-1")
    assert_equal [a_b_1_1_platform], Gem::Specification.find_all_by_full_name("a-b-1-1-x86-linux")

    assert_equal [], Gem::Specification.find_all_by_full_name("monkeys")
    assert_equal [], Gem::Specification.find_all_by_full_name("a-1-foo")
  end

  def test_find_by_name
    install_specs util_spec "a"
    install_specs util_spec "a", 1

    assert Gem::Specification.find_by_name "a"
    assert Gem::Specification.find_by_name "a", "1"
    assert Gem::Specification.find_by_name "a", ">1"

    assert_raise Gem::MissingSpecError do
      Gem::Specification.find_by_name "monkeys"
    end
  end

  def test_find_by_name_with_only_prereleases
    q = util_spec "q", "2.a"
    install_specs q

    assert Gem::Specification.find_by_name "q"
  end

  def test_find_by_name_prerelease
    b = util_spec "b", "2.a"

    b.activate

    install_specs b

    assert Gem::Specification.find_by_name "b"

    assert_raise Gem::MissingSpecVersionError do
      Gem::Specification.find_by_name "b", "1"
    end

    assert Gem::Specification.find_by_name "b", ">1"
  end

  def test_find_by_path
    a = util_spec "foo", "1", nil, "lib/foo.rb"

    install_specs a

    assert_equal a, Gem::Specification.find_by_path('foo')
    a.activate
    assert_equal a, Gem::Specification.find_by_path('foo')
  end

  def test_find_inactive_by_path
    a = util_spec "foo", "1", nil, "lib/foo.rb"

    install_specs a

    assert_equal a, Gem::Specification.find_inactive_by_path('foo')
    a.activate
    assert_nil Gem::Specification.find_inactive_by_path('foo')
  end

  def test_load_default_gem
    Gem::Specification.reset
    assert_equal [], Gem::Specification.map(&:full_name)

    default_gem_spec = new_default_spec("default", "2.0.0.0",
                                        nil, "default/gem.rb")
    spec_path = File.join(@gemhome, "specifications", "default", default_gem_spec.spec_name)
    write_file(spec_path) do |file|
      file.print(default_gem_spec.to_ruby)
    end
    Gem::Specification.reset
    assert_equal ["default-2.0.0.0"], Gem::Specification.map(&:full_name)
  end

  def util_setup_deps
    @gem = util_spec "awesome", "1.0" do |awesome|
      awesome.add_runtime_dependency "bonobo", []
      awesome.add_development_dependency "monkey", []
    end

    @bonobo = Gem::Dependency.new("bonobo", [])
    @monkey = Gem::Dependency.new("monkey", [], :development)
  end

  def util_setup_validate
    Dir.chdir @tempdir do
      FileUtils.mkdir_p File.join("ext", "a")
      FileUtils.mkdir_p "lib"
      FileUtils.mkdir_p "test"
      FileUtils.mkdir_p "bin"

      begin
        umask_orig = File.umask(2)
        FileUtils.touch File.join("ext", "a", "extconf.rb")
        FileUtils.touch File.join("lib", "code.rb")
        FileUtils.touch File.join("test", "suite.rb")

        File.open "bin/exec", "w", 0755 do |fp|
          fp.puts "#!#{Gem.ruby}"
        end
      ensure
        File.umask(umask_orig)
      end
    end
  end

  def silence_warnings
    old_verbose, $VERBOSE = $VERBOSE, false
    yield
  ensure
    $VERBOSE = old_verbose
  end
end
