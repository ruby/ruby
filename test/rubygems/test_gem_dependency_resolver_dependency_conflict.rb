require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverDependencyConflict < Gem::TestCase

  def test_explanation
    root  =
      dependency_request dep('net-ssh', '>= 2.0.13'), 'rye', '0.9.8'
    child =
      dependency_request dep('net-ssh', '>= 2.6.5'), 'net-ssh', '2.2.2', root

    conflict =
      Gem::DependencyResolver::DependencyConflict.new child, child.requester

    expected = <<-EXPECTED
  Activated net-ssh-2.2.2 instead of (>= 2.6.5) via:
    net-ssh-2.2.2, rye-0.9.8
    EXPECTED

    assert_equal expected, conflict.explanation
  end

  def test_explanation_user_request
    @DR = Gem::DependencyResolver

    spec = util_spec 'a', 2

    a1_req = @DR::DependencyRequest.new dep('a', '= 1'), nil
    a2_req = @DR::DependencyRequest.new dep('a', '= 2'), nil

    activated = @DR::ActivationRequest.new spec, a2_req

    conflict = @DR::DependencyConflict.new a1_req, activated

    expected = <<-EXPECTED
  Activated a-2 instead of (= 1) via:
    user request (gem command or Gemfile)
    EXPECTED

    assert_equal expected, conflict.explanation
  end

  def test_request_path
    root  =
      dependency_request dep('net-ssh', '>= 2.0.13'), 'rye', '0.9.8'
    child =
      dependency_request dep('net-ssh', '>= 2.6.5'), 'net-ssh', '2.2.2', root

    conflict =
      Gem::DependencyResolver::DependencyConflict.new child, nil

    assert_equal %w[net-ssh-2.2.2 rye-0.9.8], conflict.request_path
  end

end

