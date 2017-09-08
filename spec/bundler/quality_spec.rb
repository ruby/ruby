# frozen_string_literal: true
require "spec_helper"

if defined?(Encoding) && Encoding.default_external.name != "UTF-8"
  # Poor man's ruby -E UTF-8, since it works on 1.8.7
  Encoding.default_external = Encoding.find("UTF-8")
end

RSpec.describe "The library itself" do
  def check_for_spec_defs_with_single_quotes(filename)
    failing_lines = []

    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ /^ *(describe|it|context) {1}'{1}/
    end

    return if failing_lines.empty?
    "#{filename} uses inconsistent single quotes on lines #{failing_lines.join(", ")}"
  end

  def check_for_debugging_mechanisms(filename)
    debugging_mechanisms_regex = /
      (binding\.pry)|
      (debugger)|
      (sleep\s*\(?\d+)|
      (fit\s*\(?("|\w))
    /x

    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
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
    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ merge_conflicts_regex
    end

    return if failing_lines.empty?
    "#{filename} has unresolved git merge conflicts on lines #{failing_lines.join(", ")}"
  end

  def check_for_tab_characters(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ /\t/
    end

    return if failing_lines.empty?
    "#{filename} has tab characters on lines #{failing_lines.join(", ")}"
  end

  def check_for_extra_spaces(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      next if line =~ /^\s+#.*\s+\n$/
      next if %w(LICENCE.md).include?(line)
      failing_lines << number + 1 if line =~ /\s+\n$/
    end

    return if failing_lines.empty?
    "#{filename} has spaces on the EOL on lines #{failing_lines.join(", ")}"
  end

  def check_for_expendable_words(filename)
    failing_line_message = []
    useless_words = %w(
      actually
      basically
      clearly
      just
      obviously
      really
      simply
    )
    pattern = /\b#{Regexp.union(useless_words)}\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = pattern.match(line)
      failing_line_message << "#{filename} has '#{word_found}' on line #{number + 1}. Avoid using these kinds of weak modifiers."
    end

    failing_line_message unless failing_line_message.empty?
  end

  def check_for_specific_pronouns(filename)
    failing_line_message = []
    specific_pronouns = /\b(he|she|his|hers|him|her|himself|herself)\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = specific_pronouns.match(line)
      failing_line_message << "#{filename} has '#{word_found}' on line #{number + 1}. Use more generic pronouns in documentation."
    end

    failing_line_message unless failing_line_message.empty?
  end

  RSpec::Matchers.define :be_well_formed do
    match(&:empty?)

    failure_message do |actual|
      actual.join("\n")
    end
  end

  it "has no malformed whitespace", :ruby_repo do
    exempt = /\.gitmodules|\.marshal|fixtures|vendor|ssl_certs|LICENSE/
    error_messages = []
    Dir.chdir(File.expand_path("../..", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_tab_characters(filename)
        error_messages << check_for_extra_spaces(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "uses double-quotes consistently in specs", :ruby_repo do
    included = /spec/
    error_messages = []
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_spec_defs_with_single_quotes(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any leftover debugging or development mechanisms", :ruby_repo do
    exempt = %r{quality_spec.rb|support/helpers}
    error_messages = []
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_debugging_mechanisms(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any unresolved merge conflicts", :ruby_repo do
    error_messages = []
    exempt = %r{lock/lockfile_spec|quality_spec}
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_git_merge_conflicts(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of the documentation", :ruby_repo do
    included = /ronn/
    error_messages = []
    Dir.chdir(File.expand_path("../../man", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of sentences used in source code", :ruby_repo do
    error_messages = []
    exempt = /vendor/
    Dir.chdir(File.expand_path("../../lib", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "documents all used settings", :ruby_repo do
    exemptions = %w(
      gem.coc
      gem.mit
      inline
      warned_version
    )

    all_settings = Hash.new {|h, k| h[k] = [] }
    documented_settings = exemptions

    Bundler::Settings::BOOL_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::BOOL_KEYS" }
    Bundler::Settings::NUMBER_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::NUMBER_KEYS" }

    Dir.chdir(File.expand_path("../../lib", __FILE__)) do
      key_pattern = /([a-z\._-]+)/i
      `git ls-files -z`.split("\x0").each do |filename|
        File.readlines(filename).each_with_index do |line, number|
          line.scan(/Bundler\.settings\[:#{key_pattern}\]/).flatten.each {|s| all_settings[s] << "referenced at `lib/#{filename}:#{number.succ}`" }
        end
      end
      documented_settings = File.read("../man/bundle-config.ronn").scan(/^\* `#{key_pattern}`/).flatten
    end

    documented_settings.each {|s| all_settings.delete(s) }
    exemptions.each {|s| all_settings.delete(s) }
    error_messages = all_settings.map do |setting, refs|
      "The `#{setting}` setting is undocumented\n\t- #{refs.join("\n\t- ")}\n"
    end

    expect(error_messages.sort).to be_well_formed
  end

  it "can still be built", :ruby_repo do
    Dir.chdir(root) do
      begin
        gem_command! :build, "bundler.gemspec"
        if Bundler.rubygems.provides?(">= 2.4")
          # older rubygems have weird warnings, and we won't actually be using them
          # to build the gem for releases anyways
          expect(err).to be_empty, "bundler should build as a gem without warnings, but\n#{err}"
        end
      ensure
        # clean up the .gem generated
        FileUtils.rm("bundler-#{Bundler::VERSION}.gem")
      end
    end
  end

  it "does not contain any warnings", :ruby_repo do
    Dir.chdir(root.join("lib")) do
      exclusions = %w(
        bundler/capistrano.rb
        bundler/gem_tasks.rb
        bundler/vlad.rb
      )
      lib_files = `git ls-files -z`.split("\x0").grep(/\.rb$/) - exclusions
      lib_files.reject! {|f| f.start_with?("bundler/vendor") }
      lib_files.map! {|f| f.chomp(".rb") }
      sys_exec!("ruby -w -I.") do |input, _, _|
        lib_files.each do |f|
          input.puts "require '#{f}'"
        end
      end

      expect(@err.split("\n")).to be_well_formed
      expect(@out.split("\n")).to be_well_formed
    end
  end
end
