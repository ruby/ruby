require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolver < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver
  end

  def make_dep(name, *req)
    Gem::Dependency.new(name, *req)
  end

  def set(*specs)
    StaticSet.new(specs)
  end

  def assert_resolves_to expected, resolver
    actual = resolver.resolve

    exp = expected.sort_by { |s| s.full_name }
    act = actual.map { |a| a.spec }.sort_by { |s| s.full_name }

    msg = "Set of gems was not the same: #{exp.map { |x| x.full_name}.inspect} != #{act.map { |x| x.full_name}.inspect}"

    assert_equal exp, act, msg
  rescue Gem::DependencyResolutionError => e
    flunk e.message
  end

  def test_self_compose_sets_multiple
    index_set  = @DR::IndexSet.new
    vendor_set = @DR::VendorSet.new

    composed = @DR.compose_sets index_set, vendor_set

    assert_kind_of Gem::DependencyResolver::ComposedSet, composed

    assert_equal [index_set, vendor_set], composed.sets
  end

  def test_self_compose_sets_nil
    index_set  = @DR::IndexSet.new

    composed = @DR.compose_sets index_set, nil

    assert_same index_set, composed

    e = assert_raises ArgumentError do
      @DR.compose_sets nil
    end

    assert_equal 'one set in the composition must be non-nil', e.message
  end

  def test_self_compose_sets_single
    index_set  = @DR::IndexSet.new

    composed = @DR.compose_sets index_set

    assert_same index_set, composed
  end

  def test_handle_conflict
    a1 = util_spec 'a', 1

    r1 = Gem::DependencyResolver::DependencyRequest.new dep('a', '= 1'), nil
    r2 = Gem::DependencyResolver::DependencyRequest.new dep('a', '= 2'), nil
    r3 = Gem::DependencyResolver::DependencyRequest.new dep('a', '= 3'), nil

    existing = Gem::DependencyResolver::ActivationRequest.new a1, r1, false

    res = Gem::DependencyResolver.new [a1]

    res.handle_conflict r2, existing
    res.handle_conflict r2, existing
    res.handle_conflict r3, existing

    assert_equal 2, res.conflicts.length
  end

  def test_no_overlap_specificly
    a = util_spec "a", '1'
    b = util_spec "b", "1"

    ad = make_dep "a", "= 1"
    bd = make_dep "b", "= 1"

    deps = [ad, bd]

    s = set(a, b)

    res = Gem::DependencyResolver.new(deps, s)

    assert_resolves_to [a, b], res
  end

  def test_pulls_in_dependencies
    a = util_spec "a", '1'
    b = util_spec "b", "1", "c" => "= 1"
    c = util_spec "c", "1"

    ad = make_dep "a", "= 1"
    bd = make_dep "b", "= 1"

    deps = [ad, bd]

    s = set(a, b, c)

    res = Gem::DependencyResolver.new(deps, s)

    assert_resolves_to [a, b, c], res
  end

  def test_picks_highest_version
    a1 = util_spec "a", '1'
    a2 = util_spec "a", '2'

    s = set(a1, a2)

    ad = make_dep "a"

    res = Gem::DependencyResolver.new([ad], s)

    assert_resolves_to [a2], res
  end

  def test_picks_best_platform
    is      = Gem::DependencyResolver::IndexSpecification
    unknown = Gem::Platform.new 'unknown'
    a2_p1   = a3_p2 = nil

    spec_fetcher do |fetcher|
      a2_p1 = fetcher.spec 'a', 2 do |s| s.platform = Gem::Platform.local end
      a3_p2 = fetcher.spec 'a', 3 do |s| s.platform = unknown end
    end

    v2 = v(2)
    v3 = v(3)
    source = Gem::Source.new @gem_repo

    s = set

    a2    = is.new s, 'a', v2, source, Gem::Platform::RUBY
    a2_p1 = is.new s, 'a', v2, source, Gem::Platform.local.to_s
    a3_p2 = is.new s, 'a', v3, source, unknown

    s.add a3_p2
    s.add a2_p1
    s.add a2

    ad = make_dep "a"

    res = Gem::DependencyResolver.new([ad], s)

    assert_resolves_to [a2_p1], res
  end

  def test_only_returns_spec_once
    a1 = util_spec "a", "1", "c" => "= 1"
    b1 = util_spec "b", "1", "c" => "= 1"

    c1 = util_spec "c", "1"

    ad = make_dep "a"
    bd = make_dep "b"

    s = set(a1, b1, c1)

    res = Gem::DependencyResolver.new([ad, bd], s)

    assert_resolves_to [a1, b1, c1], res
  end

  def test_picks_lower_version_when_needed
    a1 = util_spec "a", "1", "c" => ">= 1"
    b1 = util_spec "b", "1", "c" => "= 1"

    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"

    ad = make_dep "a"
    bd = make_dep "b"

    s = set(a1, b1, c1, c2)

    res = Gem::DependencyResolver.new([ad, bd], s)

    assert_resolves_to [a1, b1, c1], res

    cons = res.conflicts

    assert_equal 1, cons.size
    con = cons.first

    assert_equal "c (= 1)", con.dependency.to_s
    assert_equal "c-2", con.activated.full_name
  end

  def test_conflict_resolution_only_effects_correct_spec
    a1 = util_spec "a", "1", "c" => ">= 1"
    b1 = util_spec "b", "1", "d" => ">= 1"

    d3 = util_spec "d", "3", "c" => "= 1"
    d4 = util_spec "d", "4", "c" => "= 1"

    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"

    ad = make_dep "a"
    bd = make_dep "b"

    s = set(a1, b1, d3, d4, c1, c2)

    res = Gem::DependencyResolver.new([ad, bd], s)

    assert_resolves_to [a1, b1, c1, d4], res

    cons = res.conflicts

    assert_equal 1, cons.size
    con = cons.first

    assert_equal "c (= 1)", con.dependency.to_s
    assert_equal "c-2", con.activated.full_name
  end

  def test_raises_dependency_error
    a1 = util_spec "a", "1", "c" => "= 1"
    b1 = util_spec "b", "1", "c" => "= 2"

    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"

    ad = make_dep "a"
    bd = make_dep "b"

    s = set(a1, b1, c1, c2)

    r = Gem::DependencyResolver.new([ad, bd], s)

    e = assert_raises Gem::DependencyResolutionError do
      r.resolve
    end

    deps = [make_dep("c", "= 2"), make_dep("c", "= 1")]
    assert_equal deps, e.conflicting_dependencies

    con = e.conflict

    act = con.activated
    assert_equal "c-1", act.spec.full_name

    parent = act.parent
    assert_equal "a-1", parent.spec.full_name

    act = con.requester
    assert_equal "b-1", act.spec.full_name
  end

  def test_raises_when_a_gem_is_missing
    ad = make_dep "a"

    r = Gem::DependencyResolver.new([ad], set)

    e = assert_raises Gem::UnsatisfiableDepedencyError do
      r.resolve
    end

    assert_equal "Unable to resolve dependency: user requested 'a (>= 0)'",
                 e.message

    assert_equal "a (>= 0)", e.dependency.to_s
  end

  def test_raises_when_a_gem_version_is_missing
    a1 = util_spec "a", "1"

    ad = make_dep "a", "= 3"

    r = Gem::DependencyResolver.new([ad], set(a1))

    e = assert_raises Gem::UnsatisfiableDepedencyError do
      r.resolve
    end

    assert_equal "a (= 3)", e.dependency.to_s
  end

  def test_raises_and_reports_a_toplevel_request_properly
    a1 = util_spec "a", "1"
    ad = make_dep "a", "= 3"

    r = Gem::DependencyResolver.new([ad], set(a1))

    e = assert_raises Gem::UnsatisfiableDepedencyError do
      r.resolve
    end

    assert_equal "Unable to resolve dependency: user requested 'a (= 3)'",
                 e.message
  end

  def test_raises_and_reports_an_implicit_request_properly
    a1 = util_spec "a", "1" do |s|
      s.add_runtime_dependency 'b', '= 2'
    end

    ad = make_dep "a", "= 1"

    r = Gem::DependencyResolver.new([ad], set(a1))

    e = assert_raises Gem::UnsatisfiableDepedencyError do
      r.resolve
    end

    assert_equal "Unable to resolve dependency: 'a (= 1)' requires 'b (= 2)'",
                 e.message
  end

  def test_raises_when_possibles_are_exhausted
    a1 = util_spec "a", "1", "c" => ">= 2"
    b1 = util_spec "b", "1", "c" => "= 1"

    c1 = util_spec "c", "1"
    c2 = util_spec "c", "2"
    c3 = util_spec "c", "3"

    s = set(a1, b1, c1, c2, c3)

    ad = make_dep "a"
    bd = make_dep "b"

    r = Gem::DependencyResolver.new([ad, bd], s)

    e = assert_raises Gem::DependencyResolutionError do
      r.resolve
    end

    dependency = e.conflict.dependency

    assert_equal 'a', dependency.name
    assert_equal req('>= 0'), dependency.requirement

    activated = e.conflict.activated
    assert_equal 'c-2', activated.full_name

    assert_equal dep('c', '>= 2'), activated.request.dependency

    assert_equal [dep('c', '= 1'), dep('c', '>= 2')],
                 e.conflict.conflicting_dependencies
  end

  def test_keeps_resolving_after_seeing_satisfied_dep
    a1 = util_spec "a", "1", "b" => "= 1", "c" => "= 1"
    b1 = util_spec "b", "1"
    c1 = util_spec "c", "1"

    ad = make_dep "a"
    bd = make_dep "b"

    s = set(a1, b1, c1)

    r = Gem::DependencyResolver.new([ad, bd], s)

    assert_resolves_to [a1, b1, c1], r
  end

  def test_common_rack_activation_scenario
    rack100 = util_spec "rack", "1.0.0"
    rack101 = util_spec "rack", "1.0.1"

    lib1 =    util_spec "lib", "1", "rack" => ">= 1.0.1"

    rails =   util_spec "rails", "3", "actionpack" => "= 3"
    ap =      util_spec "actionpack", "3", "rack" => ">= 1.0.0"

    d1 = make_dep "rails"
    d2 = make_dep "lib"

    s = set(lib1, rails, ap, rack100, rack101)

    r = Gem::DependencyResolver.new([d1, d2], s)

    assert_resolves_to [rails, ap, rack101, lib1], r

    # check it with the deps reverse too

    r = Gem::DependencyResolver.new([d2, d1], s)

    assert_resolves_to [lib1, rack101, rails, ap], r
  end

  def test_backtracks_to_the_first_conflict
    a1 = util_spec "a", "1"
    a2 = util_spec "a", "2"
    a3 = util_spec "a", "3"
    a4 = util_spec "a", "4"

    d1 = make_dep "a"
    d2 = make_dep "a", ">= 2"
    d3 = make_dep "a", "= 1"

    s = set(a1, a2, a3, a4)

    r = Gem::DependencyResolver.new([d1, d2, d3], s)

    assert_raises Gem::DependencyResolutionError do
      r.resolve
    end
  end

  def test_resolve_conflict
    a1 = util_spec 'a', 1
    a2 = util_spec 'a', 2

    b2 = util_spec 'b', 2, 'a' => '~> 2.0'

    s = set a1, a2, b2

    a_dep = dep 'a', '~> 1.0'
    b_dep = dep 'b'

    r = Gem::DependencyResolver.new [a_dep, b_dep], s

    assert_raises Gem::DependencyResolutionError do
      r.resolve
    end
  end

  def test_resolve_bug_699
    a1 = util_spec 'a', '1', 'b' => '= 2',
                             'c' => '~> 1.0.3'

    b1 = util_spec 'b', '2', 'c' => '~> 1.0'

    c1 = util_spec 'c', '1.0.9'
    c2 = util_spec 'c', '1.1.0'
    c3 = util_spec 'c', '1.2.0'

    s = set a1, b1, c1, c2, c3

    a_dep = dep 'a', '= 1'

    r = Gem::DependencyResolver.new [a_dep], s

    assert_resolves_to [a1, b1, c1], r
  end

  def test_resolve_rollback
    a1 = util_spec 'a', 1
    a2 = util_spec 'a', 2

    b1 = util_spec 'b', 1, 'a' => '~> 1.0'
    b2 = util_spec 'b', 2, 'a' => '~> 2.0'

    s = set a1, a2, b1, b2

    a_dep = dep 'a', '~> 1.0'
    b_dep = dep 'b'

    r = Gem::DependencyResolver.new [a_dep, b_dep], s

    assert_resolves_to [a1, b1], r
  end

  # actionmailer 2.3.4
  # activemerchant 1.5.0
  # activesupport 2.3.5, 2.3.4
  # Activemerchant needs activesupport >= 2.3.2. When you require activemerchant, it will activate the latest version that meets that requirement which is 2.3.5. Actionmailer on the other hand needs activesupport = 2.3.4. When rubygems tries to activate activesupport 2.3.4, it will raise an error.


  def test_simple_activesupport_problem
    sup1  = util_spec "activesupport", "2.3.4"
    sup2  = util_spec "activesupport", "2.3.5"

    merch = util_spec "activemerchant", "1.5.0", "activesupport" => ">= 2.3.2"
    mail =  util_spec "actionmailer", "2.3.4", "activesupport" => "= 2.3.4"

    s = set(mail, merch, sup1, sup2)

    d1 = make_dep "activemerchant"
    d2 = make_dep "actionmailer"

    r = Gem::DependencyResolver.new([d1, d2], s)

    assert_resolves_to [merch, mail, sup1], r
  end

  def test_second_level_backout
    b1 = new_spec "b", "1", { "c" => ">= 1" }, "lib/b.rb"
    b2 = new_spec "b", "2", { "c" => ">= 2" }, "lib/b.rb"
    c1 = new_spec "c", "1"
    c2 = new_spec "c", "2"
    d1 = new_spec "d", "1", { "c" => "< 2" },  "lib/d.rb"
    d2 = new_spec "d", "2", { "c" => "< 2" },  "lib/d.rb"

    s = set(b1, b2, c1, c2, d1, d2)

    p1 = make_dep "b", "> 0"
    p2 = make_dep "d", "> 0"

    r = Gem::DependencyResolver.new([p1, p2], s)

    assert_resolves_to [b1, c1, d2], r
  end

  def test_select_local_platforms
    r = Gem::DependencyResolver.new nil, nil

    a1    = util_spec 'a', 1
    a1_p1 = util_spec 'a', 1 do |s| s.platform = Gem::Platform.local end
    a1_p2 = util_spec 'a', 1 do |s| s.platform = 'unknown'           end

    selected = r.select_local_platforms [a1, a1_p1, a1_p2]

    assert_equal [a1, a1_p1], selected
  end

  def test_raises_and_explains_when_platform_prevents_install
    a1 = util_spec "a", "1" do |s|
      s.platform = Gem::Platform.new %w[c p 1]
    end

    ad = make_dep "a", "= 1"

    r = Gem::DependencyResolver.new([ad], set(a1))

    e = assert_raises Gem::UnsatisfiableDepedencyError do
      r.resolve
    end

    assert_match "No match for 'a (= 1)' on this platform. Found: c-p-1",
                 e.message
  end

end

