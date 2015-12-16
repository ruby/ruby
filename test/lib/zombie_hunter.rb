# frozen_string_literal: false
module ZombieHunter
  def after_teardown
    super
    assert_empty(Process.waitall)
  end
end

Test::Unit::TestCase.include ZombieHunter
