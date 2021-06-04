require_relative '../helper'
require_relative 'change_word'

class ChangeWordTest < Test::Unit::TestCase
  def setup
    @input = 'spec/services/anything_spec'
    @cw = TreeSpell::ChangeWord.new(@input)
    @len = @input.length
  end

  def test_deleletion
    assert_match @cw.deletion(5), 'spec/ervices/anything_spec'
    assert_match @cw.deletion(@len - 1), 'spec/services/anything_spe'
    assert_match @cw.deletion(0), 'pec/services/anything_spec'
  end

  def test_substitution
    assert_match @cw.substitution(5, '$'), 'spec/$ervices/anything_spec'
    assert_match @cw.substitution(@len - 1, '$'), 'spec/services/anything_spe$'
    assert_match @cw.substitution(0, '$'), '$pec/services/anything_spec'
  end

  def test_insertion
    assert_match @cw.insertion(7, 'X'), 'spec/serXvices/anything_spec'
    assert_match @cw.insertion(0, 'X'), 'Xspec/services/anything_spec'
    assert_match @cw.insertion(@len - 1, 'X'), 'spec/services/anything_specX'
  end

  def test_transposition
    n = @input.length
    assert_match @cw.transposition(0, -1), 'psec/services/anything_spec'
    assert_match @cw.transposition(n - 1, +1), 'spec/services/anything_spce'
    assert_match @cw.transposition(4, +1), 'specs/ervices/anything_spec'
    assert_match @cw.transposition(4, -1), 'spe/cservices/anything_spec'
    assert_match @cw.transposition(21, -1), 'spec/services/anythign_spec'
    assert_match @cw.transposition(21, +1), 'spec/services/anythin_gspec'
  end
end
