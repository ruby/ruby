# frozen_string_literal: true

module ZombieHunter
  def after_teardown
    super
    assert_empty(Process.waitall) unless multiple_ractors?
  end
end

Test::Unit::TestCase.include ZombieHunter
