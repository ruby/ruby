require 'helper'

class ExperimentalMethodNameCorrectionTest < Test::Unit::TestCase
  def test_corrects_incorrect_ivar_name
    @number = 1
    @nubmer = nil
    error = assert_raise(NoMethodError) { @nubmer.zero? }
    remove_instance_variable :@nubmer

    assert_correction :@number, error.corrections
    assert_match "Did you mean?  @number", error.to_s
  end
end
