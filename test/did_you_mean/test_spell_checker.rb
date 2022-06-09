require_relative './helper'

class SpellCheckerTest < Test::Unit::TestCase
  def test_spell_checker_corrects_mistypes
    assert_spell 'foo',   input: 'doo',   dictionary: ['foo', 'fork']
    assert_spell 'email', input: 'meail', dictionary: ['email', 'fail', 'eval']
    assert_spell 'fail',  input: 'fial',  dictionary: ['email', 'fail', 'eval']
    assert_spell 'fail',  input: 'afil',  dictionary: ['email', 'fail', 'eval']
    assert_spell 'eval',  input: 'eavl',  dictionary: ['email', 'fail', 'eval']
    assert_spell 'eval',  input: 'veal',  dictionary: ['email', 'fail', 'eval']
    assert_spell 'sub!',  input: 'suv!',  dictionary: ['sub', 'gsub', 'sub!']
    assert_spell 'sub',   input: 'suv',   dictionary: ['sub', 'gsub', 'sub!']
    assert_spell 'Foo',   input: 'FOo',   dictionary: ['Foo', 'FOo']

    assert_spell %w(gsub! gsub),     input: 'gsuv!', dictionary: %w(sub gsub gsub!)
    assert_spell %w(sub! sub gsub!), input: 'ssub!', dictionary: %w(sub sub! gsub gsub!)

    group_methods = %w(groups group_url groups_url group_path)
    assert_spell 'groups', input: 'group',  dictionary: group_methods

    group_classes = %w(
      GroupMembership
      GroupMembershipPolicy
      GroupMembershipDecorator
      GroupMembershipSerializer
      GroupHelper
      Group
      GroupMailer
      NullGroupMembership
    )

    assert_spell 'GroupMembership',          dictionary: group_classes, input: 'GroupMemberhip'
    assert_spell 'GroupMembershipDecorator', dictionary: group_classes, input: 'GroupMemberhipDecorator'

    names = %w(first_name_change first_name_changed? first_name_will_change!)
    assert_spell names, input: 'first_name_change!', dictionary: names

    assert_empty DidYouMean::SpellChecker.new(dictionary: ['proc']).correct('product_path')
    assert_empty DidYouMean::SpellChecker.new(dictionary: ['fork']).correct('fooo')
  end

  def test_spell_checker_corrects_misspells
    assert_spell 'descendants',      input: 'dependents', dictionary: ['descendants']
    assert_spell 'drag_to',          input: 'drag',       dictionary: ['drag_to']
    assert_spell 'set_result_count', input: 'set_result', dictionary: ['set_result_count']
  end

  def test_spell_checker_sorts_results_by_simiarity
    expected = %w(
      name12345
      name1234
      name123
    )

    actual = DidYouMean::SpellChecker.new(dictionary: %w(
      name12
      name123
      name1234
      name12345
      name123456
    )).correct('name123456')

    assert_equal expected, actual
  end

  def test_spell_checker_excludes_input_from_dictionary
    assert_empty DidYouMean::SpellChecker.new(dictionary: ['input']).correct('input')
    assert_empty DidYouMean::SpellChecker.new(dictionary: [:input]).correct('input')
    assert_empty DidYouMean::SpellChecker.new(dictionary: ['input']).correct(:input)
  end

  private

  def assert_spell(expected, input: , dictionary: )
    corrections = DidYouMean::SpellChecker.new(dictionary: dictionary).correct(input)
    assert_equal Array(expected), corrections, "Expected to suggest #{expected}, but got #{corrections.inspect}"
  end
end
