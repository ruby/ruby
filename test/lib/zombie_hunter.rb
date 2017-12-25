# frozen_string_literal: true

# There might be compiler processes executed by MJIT
return if MJIT.enabled?

module ZombieHunter
  def after_teardown
    super
    assert_empty(Process.waitall)
  end
end

Test::Unit::TestCase.include ZombieHunter
