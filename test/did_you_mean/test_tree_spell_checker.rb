# frozen_string_literal: true

require "yaml"

require_relative "./helper"

class TreeSpellCheckerTest < Test::Unit::TestCase
  MINI_DIRECTORIES = YAML.load_file(File.expand_path("fixtures/mini_dir.yml", __dir__))
  RSPEC_DIRECTORIES = YAML.load_file(File.expand_path("fixtures/rspec_dir.yml", __dir__))

  def setup
    @dictionary =
      %w(
        spec/models/concerns/vixen_spec.rb
        spec/models/concerns/abcd_spec.rb
        spec/models/concerns/vixenus_spec.rb
        spec/models/concerns/efgh_spec.rb
        spec/modals/confirms/abcd_spec.rb
        spec/modals/confirms/efgh_spec.rb
        spec/models/gafafa_spec.rb
        spec/models/gfsga_spec.rb
        spec/controllers/vixen_controller_spec.rb
      )
    @test_str = "spek/modeks/confirns/viken_spec.rb"
    @tree_spell_checker = DidYouMean::TreeSpellChecker.new(dictionary: @dictionary)
  end

  def test_corrupt_root
    assert_tree_spell "test/verbose_formatter_test.rb",
                      input: "btets/cverbose_formatter_etst.rb suggestions",
                      dictionary: MINI_DIRECTORIES
  end

  def test_leafless_state
    assert_tree_spell "spec/modals/confirms/efgh_spec.rb",
                      input: "spec/modals/confirXX/efgh_spec.rb",
                      dictionary: [*@dictionary, "spec/features"]

    assert_tree_spell "spec/features",
                      input: "spec/featuresXX",
                      dictionary: [*@dictionary, "spec/features"]
  end

  def test_rake_dictionary
    assert_tree_spell "parallel:prepare",
                      input: "parallel:preprare",
                      dictionary:  %w[parallel:prepare parallel:create parallel:rake parallel:migrate],
                      separator: ":"
  end

  def test_special_words_mini
    [
      %w(test/fixtures/book.rb                           test/fixture/book.rb),
      %w(test/edit_distance/jaro_winkler_test.rb         test/edit_distace/jaro_winkler_test.rb),
      %w(test/edit_distance/jaro_winkler_test.rb         teste/dit_distane/jaro_winkler_test.rb),
      %w(test/fixtures/book.rb                           test/fixturWes/book.rb),
      %w(test/test_helper.rb                             tes!t/test_helper.rb),
      %w(test/fixtures/book.rb                           test/hfixtures/book.rb),
      %w(test/edit_distance/jaro_winkler_test.rb         test/eidt_distance/jaro_winkler_test.@rb),
      %w(test/spell_checker_test.rb                      test/spell_checke@r_test.rb),
      %w(test/tree_spell_human_typo_test.rb              testt/ree_spell_human_typo_test.rb),
      %w(test/edit_distance/jaro_winkler_test.rb         test/edit_distance/jaro_winkler_tuest.rb),
    ].each do |expected, user_input|
      assert_tree_spell expected, input: user_input, dictionary: MINI_DIRECTORIES
    end

    [
      %w(test/spell_checking/variable_name_check_test.rb test/spell_checking/vriabl_ename_check_test.rb),
      %w(test/spell_checking/key_name_check_test.rb      tesit/spell_checking/key_name_choeck_test.rb),
    ].each do |expected, user_input|
      assert_equal expected, DidYouMean::TreeSpellChecker.new(dictionary: MINI_DIRECTORIES).correct(user_input)[0]
    end
  end

  def test_special_words_rspec
    [
      %w(spec/rspec/core/formatters/exception_presenter_spec.rb spec/rspec/core/formatters/eception_presenter_spec.rb),
      %w(spec/rspec/core/metadata_spec.rb                       spec/rspec/core/metadata_spe.crb),
      %w(spec/rspec/core/ordering_spec.rb                       spec/spec/core/odrering_spec.rb),
      %w(spec/support/mathn_integration_support.rb              spec/support/mathn_itegrtion_support.rb),
    ].each do |expected, user_input|
      assert_tree_spell expected, input: user_input, dictionary: RSPEC_DIRECTORIES
    end
  end

  def test_file_in_root
    assert_tree_spell "test/spell_checker_test.rb", input: "test/spell_checker_test.r", dictionary: MINI_DIRECTORIES
  end

  def test_no_plausible_states
    assert_tree_spell [], input: "testspell_checker_test.rb", dictionary: MINI_DIRECTORIES
  end

  def test_no_plausible_states_with_augmentation
    assert_tree_spell [], input: "testspell_checker_test.rb", dictionary: MINI_DIRECTORIES

    suggestions = DidYouMean::TreeSpellChecker.new(dictionary: MINI_DIRECTORIES, augment: true).correct("testspell_checker_test.rb")

    assert_equal suggestions.first, "test/spell_checker_test.rb"
  end

  def test_no_idea_with_augmentation
    assert_tree_spell [], input: "test/spell_checking/key_name.rb", dictionary: MINI_DIRECTORIES

    suggestions = DidYouMean::TreeSpellChecker.new(dictionary: MINI_DIRECTORIES, augment: true).correct("test/spell_checking/key_name.rb")

    assert_equal suggestions.first, "test/spell_checking/key_name_check_test.rb"
  end

  def test_works_out_suggestions
    assert_tree_spell %w(spec/models/concerns/vixen_spec.rb spec/models/concerns/vixenus_spec.rb),
                      input: "spek/modeks/confirns/viken_spec.rb",
                      dictionary: %w(spec/models/concerns/vixen_spec.rb spec/models/concerns/vixenus_spec.rb)
  end

  def test_works_when_input_is_correct
    assert_tree_spell "spec/models/concerns/vixenus_spec.rb",
                      input: "spec/models/concerns/vixenus_spec.rb",
                      dictionary: @dictionary
  end

  def test_find_out_leaves_in_a_path
    names = @tree_spell_checker.find_leaves("spec/modals/confirms")

    assert_equal %w[abcd_spec.rb efgh_spec.rb], names
  end

  def test_works_out_nodes
    exp_paths = ["spec/models/concerns",
                 "spec/models/confirms",
                 "spec/modals/concerns",
                 "spec/modals/confirms",
                 "spec/controllers/concerns",
                 "spec/controllers/confirms"]

    states = @tree_spell_checker.dimensions
    nodes  = states[0].product(*states[1..-1])
    paths  = @tree_spell_checker.possible_paths(nodes)

    assert_equal paths, exp_paths
  end

  def test_works_out_state_space
    suggestions = @tree_spell_checker.plausible_dimensions(@test_str)

    assert_equal [["spec"], %w[models modals], %w[confirms concerns]], suggestions
  end

  def test_parses_dictionary
    states = @tree_spell_checker.dimensions

    assert_equal [["spec"], %w[models modals controllers], %w[concerns confirms]], states
  end

  def test_parses_elementary_dictionary
    dimensions = DidYouMean::TreeSpellChecker
                   .new(dictionary: %w(spec/models/user_spec.rb spec/services/account_spec.rb))
                   .dimensions

    assert_equal [["spec"], %w[models services]], dimensions
  end

  private

  def assert_tree_spell(expected, input:, dictionary:, separator: "/")
    suggestions = DidYouMean::TreeSpellChecker.new(dictionary: dictionary, separator: separator).correct(input)

    assert_equal Array(expected), suggestions, "Expected to suggest #{expected}, but got #{suggestions.inspect}"
  end
end
