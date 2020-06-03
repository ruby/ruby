# frozen_string_literal: true

require "set"

RSpec.describe "The library itself" do
  def check_for_debugging_mechanisms(filename)
    debugging_mechanisms_regex = /
      (binding\.pry)|
      (debugger)|
      (sleep\s*\(?\d+)|
      (fit\s*\(?("|\w))
    /x

    failing_lines = []
    each_line(filename) do |line, number|
      if line =~ debugging_mechanisms_regex && !line.end_with?("# ignore quality_spec\n")
        failing_lines << number + 1
      end
    end

    return if failing_lines.empty?
    "#{filename} has debugging mechanisms (like binding.pry, sleep, debugger, rspec focusing, etc.) on lines #{failing_lines.join(", ")}"
  end

  def check_for_git_merge_conflicts(filename)
    merge_conflicts_regex = /
      <<<<<<<|
      =======|
      >>>>>>>
    /x

    failing_lines = []
    each_line(filename) do |line, number|
      failing_lines << number + 1 if line =~ merge_conflicts_regex
    end

    return if failing_lines.empty?
    "#{filename} has unresolved git merge conflicts on lines #{failing_lines.join(", ")}"
  end

  def check_for_tab_characters(filename)
    failing_lines = []
    each_line(filename) do |line, number|
      failing_lines << number + 1 if line =~ /\t/
    end

    return if failing_lines.empty?
    "#{filename} has tab characters on lines #{failing_lines.join(", ")}"
  end

  def check_for_extra_spaces(filename)
    failing_lines = []
    each_line(filename) do |line, number|
      next if line =~ /^\s+#.*\s+\n$/
      failing_lines << number + 1 if line =~ /\s+\n$/
    end

    return if failing_lines.empty?
    "#{filename} has spaces on the EOL on lines #{failing_lines.join(", ")}"
  end

  def check_for_straneous_quotes(filename)
    return if File.expand_path(filename) == __FILE__

    failing_lines = []
    each_line(filename) do |line, number|
      failing_lines << number + 1 if line =~ /’/
    end

    return if failing_lines.empty?
    "#{filename} has an straneous quote on lines #{failing_lines.join(", ")}"
  end

  def check_for_expendable_words(filename)
    failing_line_message = []
    useless_words = %w[
      actually
      basically
      clearly
      just
      obviously
      really
      simply
    ]
    pattern = /\b#{Regexp.union(useless_words)}\b/i

    each_line(filename) do |line, number|
      next unless word_found = pattern.match(line)
      failing_line_message << "#{filename}:#{number.succ} has '#{word_found}'. Avoid using these kinds of weak modifiers."
    end

    failing_line_message unless failing_line_message.empty?
  end

  def check_for_specific_pronouns(filename)
    failing_line_message = []
    specific_pronouns = /\b(he|she|his|hers|him|her|himself|herself)\b/i

    each_line(filename) do |line, number|
      next unless word_found = specific_pronouns.match(line)
      failing_line_message << "#{filename}:#{number.succ} has '#{word_found}'. Use more generic pronouns in documentation."
    end

    failing_line_message unless failing_line_message.empty?
  end

  it "has no malformed whitespace" do
    exempt = /\.gitmodules|fixtures|vendor|LICENSE|vcr_cassettes|rbreadline\.diff|\.txt$/
    error_messages = []
    tracked_files.each do |filename|
      next if filename =~ exempt
      error_messages << check_for_tab_characters(filename)
      error_messages << check_for_extra_spaces(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "has no estraneous quotes" do
    exempt = /vendor|vcr_cassettes|LICENSE|rbreadline\.diff/
    error_messages = []
    tracked_files.each do |filename|
      next if filename =~ exempt
      error_messages << check_for_straneous_quotes(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any leftover debugging or development mechanisms" do
    exempt = %r{quality_spec.rb|support/helpers|vcr_cassettes|\.md|\.ronn|\.txt|\.5|\.1}
    error_messages = []
    tracked_files.each do |filename|
      next if filename =~ exempt
      error_messages << check_for_debugging_mechanisms(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any unresolved merge conflicts" do
    error_messages = []
    exempt = %r{lock/lockfile_spec|quality_spec|vcr_cassettes|\.ronn|lockfile_parser\.rb}
    tracked_files.each do |filename|
      next if filename =~ exempt
      error_messages << check_for_git_merge_conflicts(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of the documentation" do
    included = /ronn/
    error_messages = []
    man_tracked_files.each do |filename|
      next unless filename =~ included
      error_messages << check_for_expendable_words(filename)
      error_messages << check_for_specific_pronouns(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of sentences used in source code" do
    error_messages = []
    exempt = /vendor|vcr_cassettes|CODE_OF_CONDUCT/
    lib_tracked_files.each do |filename|
      next if filename =~ exempt
      error_messages << check_for_expendable_words(filename)
      error_messages << check_for_specific_pronouns(filename)
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "documents all used settings" do
    exemptions = %w[
      deployment_means_frozen
      forget_cli_options
      gem.coc
      gem.mit
      inline
      use_gem_version_promoter_for_major_updates
    ]

    all_settings = Hash.new {|h, k| h[k] = [] }
    documented_settings = []

    Bundler::Settings::BOOL_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::BOOL_KEYS" }
    Bundler::Settings::NUMBER_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::NUMBER_KEYS" }
    Bundler::Settings::ARRAY_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::ARRAY_KEYS" }

    key_pattern = /([a-z\._-]+)/i
    lib_tracked_files.each do |filename|
      each_line(filename) do |line, number|
        line.scan(/Bundler\.settings\[:#{key_pattern}\]/).flatten.each {|s| all_settings[s] << "referenced at `#{filename}:#{number.succ}`" }
      end
    end
    documented_settings = File.read("man/bundle-config.ronn")[/LIST OF AVAILABLE KEYS.*/m].scan(/^\* `#{key_pattern}`/).flatten

    documented_settings.each do |s|
      all_settings.delete(s)
      expect(exemptions.delete(s)).to be_nil, "setting #{s} was exempted but was actually documented"
    end

    exemptions.each do |s|
      expect(all_settings.delete(s)).to be_truthy, "setting #{s} was exempted but unused"
    end
    error_messages = all_settings.map do |setting, refs|
      "The `#{setting}` setting is undocumented\n\t- #{refs.join("\n\t- ")}\n"
    end

    expect(error_messages.sort).to be_well_formed

    expect(documented_settings).to be_sorted
  end

  it "can still be built" do
    with_built_bundler do |_gem_path|
      expect(err).to be_empty, "bundler should build as a gem without warnings, but\n#{err}"
    end
  end

  it "ships the correct set of files" do
    git_list = git_ls_files(ruby_core? ? "lib/bundler lib/bundler.rb man/bundle* man/gemfile* libexec/bundle*" : "lib man exe CHANGELOG.md LICENSE.md README.md bundler.gemspec")

    gem_list = loaded_gemspec.files

    expect(git_list.to_set).to eq(gem_list.to_set)
  end

  it "does not contain any warnings" do
    exclusions = %w[
      lib/bundler/capistrano.rb
      lib/bundler/deployment.rb
      lib/bundler/gem_tasks.rb
      lib/bundler/vlad.rb
      lib/bundler/templates/gems.rb
    ]
    files_to_require = lib_tracked_files.grep(/\.rb$/) - exclusions
    files_to_require.reject! {|f| f.start_with?("lib/bundler/vendor") }
    files_to_require.map! {|f| File.expand_path(f, source_root) }
    files_to_require.sort!
    sys_exec("ruby -w") do |input, _, _|
      files_to_require.each do |f|
        input.puts "require '#{f}'"
      end
    end

    warnings = last_command.stdboth.split("\n")
    # ignore warnings around deprecated Object#=~ method in RubyGems
    warnings.reject! {|w| w =~ %r{rubygems\/version.rb.*deprecated\ Object#=~} }

    expect(warnings).to be_well_formed
  end

  it "does not use require internally, but require_relative" do
    exempt = %r{templates/|vendor/}
    all_bad_requires = []
    lib_tracked_files.each do |filename|
      next if filename =~ exempt
      each_line(filename) do |line, number|
        line.scan(/^ *require "bundler/).each { all_bad_requires << "#{filename}:#{number.succ}" }
      end
    end

    expect(all_bad_requires).to be_empty, "#{all_bad_requires.size} internal requires that should use `require_relative`: #{all_bad_requires}"
  end

private

  def each_line(filename, &block)
    File.readlines(filename, :encoding => "UTF-8").each_with_index(&block)
  end
end
