require 'helper'
require 'set'
require 'yaml'
require_relative 'human_typo'

# statistical tests on tree_spell algorithms
class ExploreTest < Test::Unit::TestCase
  MINI_DIRECTORIES = YAML.load_file(File.expand_path('../fixtures/mini_dir.yml', __dir__))
  RSPEC_DIRECTORIES = YAML.load_file(File.expand_path('../fixtures/rspec_dir.yml', __dir__))

  def test_checkers_with_many_typos_on_mini
    n_repeat = 10_000
    many_typos n_repeat, MINI_DIRECTORIES, 'Minitest'
  end

  def test_checkers_with_many_typos_on_rspec
    n_repeat = 10_000
    many_typos n_repeat, RSPEC_DIRECTORIES, 'Rspec'
  end

  def test_human_typo
    n_repeat = 10_000
    total_changes = 0
    word = 'any_string_that_is_40_characters_long_sp'
    n_repeat.times do
      word_error = TreeSpell::HumanTypo.new(word).call
      total_changes += DidYouMean::Levenshtein.distance(word, word_error)
    end
    mean_changes = (total_changes.to_f / n_repeat).round(2)
    puts ''
    puts "HumanTypo mean_changes: #{mean_changes} with n_repeat: #{n_repeat}"
    puts 'Expected  mean_changes: 2.1 with n_repeat: 10000, plus/minus 0.03'
    puts ''
  end

  def test_execution_speed
    n_repeat = 1_000
    puts ''
    puts 'Testing execution time of Standard'
    measure_execution_speed(n_repeat) do |files, error|
      DidYouMean::SpellChecker.new(dictionary: files).correct error
    end
    puts ''
    puts 'Testing execution time of Tree'
    measure_execution_speed(n_repeat) do |files, error|
      DidYouMean::TreeSpellChecker.new(dictionary: files).correct error
    end
    puts ''
    puts 'Testing execution time of Augmented Tree'
    measure_execution_speed(n_repeat) do |files, error|
      DidYouMean::TreeSpellChecker.new(dictionary: files, augment: true).correct error
    end
  end

  private

  def measure_execution_speed(n_repeat, &block)
    len = RSPEC_DIRECTORIES.length
    start_time = Time.now
    n_repeat.times do
      word = RSPEC_DIRECTORIES[rand len]
      word_error = TreeSpell::HumanTypo.new(word).call
      block.call(RSPEC_DIRECTORIES, word_error)
    end
    time_ms = (Time.now - start_time).to_f * 1000 / n_repeat
    puts "Average time (ms): #{time_ms.round(1)}"
  end

  def many_typos(n_repeat, files, title)
    first_times = [0, 0, 0]
    total_suggestions = [0, 0, 0]
    total_failures = [0, 0, 0]
    len = files.length
    n_repeat.times do
      word = files[rand len]
      word_error = TreeSpell::HumanTypo.new(word).call
      suggestions_a = group_suggestions word_error, files
      check_first_is_right word, suggestions_a, first_times
      check_no_suggestions suggestions_a, total_suggestions
      check_for_failure word, suggestions_a, total_failures
    end
    print_results first_times, total_suggestions, total_failures, n_repeat, title
  end

  def group_suggestions(word_error, files)
    a0 = DidYouMean::TreeSpellChecker.new(dictionary: files).correct word_error
    a1 = ::DidYouMean::SpellChecker.new(dictionary: files).correct word_error
    a2 =  a0.empty? ? a1 : a0
    [a0, a1, a2]
  end

  def check_for_failure(word, suggestions_a, total_failures)
    suggestions_a.each_with_index.map do |a, i|
      total_failures[i] += 1 unless a.include? word
    end
  end

  def check_first_is_right(word, suggestions_a, first_times)
    suggestions_a.each_with_index.map do |a, i|
      first_times[i] += 1 if word == a.first
    end
  end

  def check_no_suggestions(suggestions_a, total_suggestions)
    suggestions_a.each_with_index.map do |a, i|
      total_suggestions[i] += a.length
    end
  end

  def print_results(first_times, total_suggestions, total_failures, n_repeat, title)
    algorithms = ['Tree     ', 'Standard ', 'Augmented']
    print_header title
    (0..2).each do |i|
      ft = (first_times[i].to_f / n_repeat * 100).round(1)
      mns = (total_suggestions[i].to_f / (n_repeat - total_failures[i])).round(1)
      f = (total_failures[i].to_f / n_repeat * 100).round(1)
      puts " #{algorithms[i]}  #{' ' * 7}  #{ft} #{' ' * 14} #{mns} #{' ' * 15} #{f} #{' ' * 16}"
    end
  end

  def print_header(title)
    puts "#{' ' * 30} #{title} Summary #{' ' * 31}"
    puts '-' * 80
    puts " Method  |   First Time (\%)    Mean Suggestions       Failures (\%) #{' ' * 13}"
    puts '-' * 80
  end
end
