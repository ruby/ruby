# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverConflict < Gem::TestCase

  def test_explanation
    root  =
      dependency_request dep('net-ssh', '>= 2.0.13'), 'rye', '0.9.8'
    child =
      dependency_request dep('net-ssh', '>= 2.6.5'), 'net-ssh', '2.2.2', root

    dep = Gem::Resolver::DependencyRequest.new dep('net-ssh', '>= 2.0.13'), nil

    spec = util_spec 'net-ssh', '2.2.2'
    active =
      Gem::Resolver::ActivationRequest.new spec, dep

    conflict =
      Gem::Resolver::Conflict.new child, active

    expected = <<-EXPECTED
  Activated net-ssh-2.2.2
  which does not match conflicting dependency (>= 2.6.5)

  Conflicting dependency chains:
    net-ssh (>= 2.0.13), 2.2.2 activated

  versus:
    rye (= 0.9.8), 0.9.8 activated, depends on
    net-ssh (>= 2.0.13), 2.2.2 activated, depends on
    net-ssh (>= 2.6.5)

    EXPECTED

    assert_equal expected, conflict.explanation
  end

  def test_explanation_user_request
    @DR = Gem::Resolver

    spec = util_spec 'a', 2

    a1_req = @DR::DependencyRequest.new dep('a', '= 1'), nil
    a2_req = @DR::DependencyRequest.new dep('a', '= 2'), nil

    activated = @DR::ActivationRequest.new spec, a2_req

    conflict = @DR::Conflict.new a1_req, activated

    expected = <<-EXPECTED
  Activated a-2
  which does not match conflicting dependency (= 1)

  Conflicting dependency chains:
    a (= 2), 2 activated

  versus:
    a (= 1)

    EXPECTED

    assert_equal expected, conflict.explanation
  end

  def test_request_path
    root  =
      dependency_request dep('net-ssh', '>= 2.0.13'), 'rye', '0.9.8'

    child =
      dependency_request dep('other', '>= 1.0'), 'net-ssh', '2.2.2', root

    conflict =
      Gem::Resolver::Conflict.new nil, nil

    expected = [
      'net-ssh (>= 2.0.13), 2.2.2 activated',
      'rye (= 0.9.8), 0.9.8 activated'
    ]

    assert_equal expected, conflict.request_path(child.requester)
  end

end
