# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverActivationRequest < Gem::TestCase

  def setup
    super

    @DR = Gem::Resolver

    @dep = @DR::DependencyRequest.new dep('a', '>= 0'), nil

    source   = Gem::Source::Local.new
    platform = Gem::Platform::RUBY

    @a3 = @DR::IndexSpecification.new nil, 'a', v(3), source, platform

    @req = @DR::ActivationRequest.new @a3, @dep
  end

  def test_development_eh
    refute @req.development?

    dep_req = @DR::DependencyRequest.new dep('a', '>= 0', :development), nil

    act_req = @DR::ActivationRequest.new @a3, dep_req

    assert act_req.development?
  end

  def test_inspect
    assert_match 'a-3',                         @req.inspect
    assert_match 'from a (>= 0)',               @req.inspect
  end

  def test_installed_eh
    v_spec = Gem::Resolver::VendorSpecification.new nil, @a3

    @req = @DR::ActivationRequest.new v_spec, @dep

    assert @req.installed?
  end

end
