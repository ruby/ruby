require 'rubygems/test_case'

class TestGemResolverConflict < Gem::TestCase

  def test_self_compatibility
    assert_same Gem::Resolver::Conflict, Gem::Resolver::DependencyConflict
  end

  def test_explanation
    root  =
      dependency_request dep('net-ssh', '>= 2.0.13'), 'rye', '0.9.8'
    child =
      dependency_request dep('net-ssh', '>= 2.6.5'), 'net-ssh', '2.2.2', root

    dep = Gem::Resolver::DependencyRequest.new dep('net-ssh', '>= 2.0.13'), nil

    spec = quick_spec 'net-ssh', '2.2.2'
    active =
      Gem::Resolver::ActivationRequest.new spec, dep

    conflict =
      Gem::Resolver::Conflict.new child, active

    expected = <<-EXPECTED
  Activated net-ssh-2.2.2 via:
    net-ssh-2.2.2 (>= 2.0.13)
  instead of (>= 2.6.5) via:
    net-ssh-2.2.2 (>= 2.0.13), rye-0.9.8 (= 0.9.8)
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
  Activated a-2 via:
    a-2 (= 2)
  instead of (= 1) via:
    user request (gem command or Gemfile)
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
      'net-ssh-2.2.2 (>= 2.0.13)',
      'rye-0.9.8 (= 0.9.8)'
    ]

    assert_equal expected, conflict.request_path(child.requester)
  end

end

