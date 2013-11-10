require 'rubygems/test_case'

class TestGemDependencyResolverActivationRequest < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver

    @dep = @DR::DependencyRequest.new dep('a', '>= 0'), nil

    source   = Gem::Source::Local.new
    platform = Gem::Platform::RUBY

    @a1 = @DR::IndexSpecification.new nil, 'a', v(1), source, platform
    @a2 = @DR::IndexSpecification.new nil, 'a', v(2), source, platform
    @a3 = @DR::IndexSpecification.new nil, 'a', v(3), source, platform

    @req = @DR::ActivationRequest.new @a3, @dep, [@a1, @a2]
  end

  def test_inspect
    assert_match 'a-3',                         @req.inspect
    assert_match 'from a (>= 0)',               @req.inspect
    assert_match '(others possible: a-1, a-2)', @req.inspect
  end

  def test_inspect_legacy
    req = @DR::ActivationRequest.new @a3, @dep, true

    assert_match '(others possible)', req.inspect

    req = @DR::ActivationRequest.new @a3, @dep, false

    refute_match '(others possible)', req.inspect
  end

  def test_installed_eh
    v_spec = Gem::DependencyResolver::VendorSpecification.new nil, @a3

    @req = @DR::ActivationRequest.new v_spec, @dep, [@a1, @a2]

    assert @req.installed?
  end

  def test_others_possible_eh
    assert @req.others_possible?

    req = @DR::ActivationRequest.new @a3, @dep, []

    refute req.others_possible?

    req = @DR::ActivationRequest.new @a3, @dep, true

    assert req.others_possible?

    req = @DR::ActivationRequest.new @a3, @dep, false

    refute req.others_possible?
  end

end

