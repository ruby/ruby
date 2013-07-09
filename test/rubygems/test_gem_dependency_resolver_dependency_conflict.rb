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

