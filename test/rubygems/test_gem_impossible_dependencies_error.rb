# frozen_string_literal: true

require_relative "helper"

class TestGemImpossibleDependenciesError < Gem::TestCase
  def test_message_conflict
    request = dependency_request dep("net-ssh", ">= 2.0.13"), "rye", "0.9.8"

    conflicts = []

    # These conflicts are lies as their dependencies does not have the correct
    # requested-by entries, but they are suitable for testing the message.
    # See #485 to construct a correct conflict.
    net_ssh_2_2_2 =
      dependency_request dep("net-ssh", ">= 2.6.5"), "net-ssh", "2.2.2", request
    net_ssh_2_6_5 =
      dependency_request dep("net-ssh", "~> 2.2.2"), "net-ssh", "2.6.5", request

    conflict1 = Gem::Resolver::Conflict.new \
      net_ssh_2_6_5, net_ssh_2_6_5.requester

    conflict2 = Gem::Resolver::Conflict.new \
      net_ssh_2_2_2, net_ssh_2_2_2.requester

    conflicts << [net_ssh_2_6_5.requester.spec, conflict1]
    conflicts << [net_ssh_2_2_2.requester.spec, conflict2]

    error = Gem::ImpossibleDependenciesError.new request, conflicts

    expected = <<-EXPECTED
rye-0.9.8 requires net-ssh (>= 2.0.13) but it conflicted:
  Activated net-ssh-2.6.5
  which does not match conflicting dependency (~> 2.2.2)

  Conflicting dependency chains:
    rye (= 0.9.8), 0.9.8 activated, depends on
    net-ssh (>= 2.0.13), 2.6.5 activated

  versus:
    rye (= 0.9.8), 0.9.8 activated, depends on
    net-ssh (>= 2.0.13), 2.6.5 activated, depends on
    net-ssh (~> 2.2.2)

  Activated net-ssh-2.2.2
  which does not match conflicting dependency (>= 2.6.5)

  Conflicting dependency chains:
    rye (= 0.9.8), 0.9.8 activated, depends on
    net-ssh (>= 2.0.13), 2.2.2 activated

  versus:
    rye (= 0.9.8), 0.9.8 activated, depends on
    net-ssh (>= 2.0.13), 2.2.2 activated, depends on
    net-ssh (>= 2.6.5)

    EXPECTED

    assert_equal expected, error.message
  end
end
