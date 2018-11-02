# frozen_string_literal: true

if defined?(Encoding) && Encoding.default_external.name != "UTF-8"
  # Poor man's ruby -E UTF-8, since it works on 1.8.7
  Encoding.default_external = Encoding.find("UTF-8")
end

RSpec.describe "The library itself" do
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
      next if %w[LICENCE.md].include?(line)
      failing_lines << number + 1 if line =~ /\s+\n$/
    end

    return if failing_lines.empty?
    "#{filename} has spaces on the EOL on lines #{failing_lines.join(", ")}"
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

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = pattern.match(line)
      failing_line_message << "#{filename}:#{number.succ} has '#{word_found}'. Avoid using these kinds of weak modifiers."
    end

    failing_line_message unless failing_line_message.empty?
  end

  def check_for_specific_pronouns(filename)
    failing_line_message = []
    specific_pronouns = /\b(he|she|his|hers|him|her|himself|herself)\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = specific_pronouns.match(line)
      failing_line_message << "#{filename}:#{number.succ} has '#{word_found}'. Use more generic pronouns in documentation."
    end

    failing_line_message unless failing_line_message.empty?
  end

  RSpec::Matchers.define :be_well_formed do
    match(&:empty?)

    failure_message do |actual|
      actual.join("\n")
    end
  end

  it "has no malformed whitespace" do
    exempt = /\.gitmodules|\.marshal|fixtures|vendor|ssl_certs|LICENSE|vcr_cassettes/
    error_messages = []
    Dir.chdir(root) do
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb spec/bundler` : `git ls-files -z -- lib`
      lib_files.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_tab_characters(filename)
        error_messages << check_for_extra_spaces(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any leftover debugging or development mechanisms" do
    exempt = %r{quality_spec.rb|support/helpers|vcr_cassettes|\.md|\.ronn}
    error_messages = []
    Dir.chdir(root) do
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb spec/bundler` : `git ls-files -z -- lib`
      lib_files.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_debugging_mechanisms(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any unresolved merge conflicts" do
    error_messages = []
    exempt = %r{lock/lockfile_(bundler_1_)?spec|quality_spec|vcr_cassettes|\.ronn|lockfile_parser\.rb}
    Dir.chdir(root) do
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb spec/bundler` : `git ls-files -z -- lib`
      lib_files.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_git_merge_conflicts(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of the documentation" do
    included = /ronn/
    error_messages = []
    Dir.chdir(root) do
      `git ls-files -z -- man`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of sentences used in source code" do
    error_messages = []
    exempt = /vendor/
    Dir.chdir(root) do
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb` : `git ls-files -z -- lib`
      lib_files.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "documents all used settings" do
    exemptions = %w[
      auto_config_jobs
      cache_command_is_package
      console_command
      deployment_means_frozen
      forget_cli_options
      gem.coc
      gem.mit
      inline
      lockfile_uses_separate_rubygems_sources
      use_gem_version_promoter_for_major_updates
      viz_command
    ]

    all_settings = Hash.new {|h, k| h[k] = [] }
    documented_settings = []

    Bundler::Settings::BOOL_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::BOOL_KEYS" }
    Bundler::Settings::NUMBER_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::NUMBER_KEYS" }
    Bundler::Settings::ARRAY_KEYS.each {|k| all_settings[k] << "in Bundler::Settings::ARRAY_KEYS" }

    Dir.chdir(root) do
      key_pattern = /([a-z\._-]+)/i
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb` : `git ls-files -z -- lib`
      lib_files.split("\x0").each do |filename|
        File.readlines(filename).each_with_index do |line, number|
          line.scan(/Bundler\.settings\[:#{key_pattern}\]/).flatten.each {|s| all_settings[s] << "referenced at `#{filename}:#{number.succ}`" }
        end
      end
      documented_settings = File.read("man/bundle-config.ronn")[/LIST OF AVAILABLE KEYS.*/m].scan(/^\* `#{key_pattern}`/).flatten
    end

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
    Dir.chdir(root) do
      begin
        gem_command! :build, gemspec
        if Bundler.rubygems.provides?(">= 2.4")
          # there's no way aroudn this warning
          last_command.stderr.sub!(/^YAML safe loading.*/, "")

          # older rubygems have weird warnings, and we won't actually be using them
          # to build the gem for releases anyways
          expect(last_command.stderr).to be_empty, "bundler should build as a gem without warnings, but\n#{err}"
        end
      ensure
        # clean up the .gem generated
        path_prefix = ruby_core? ? "lib/" : "./"
        FileUtils.rm("#{path_prefix}bundler-#{Bundler::VERSION}.gem")
      end
    end
  end

  it "does not contain any warnings" do
    Dir.chdir(root) do
      exclusions = %w[
        lib/bundler/capistrano.rb
        lib/bundler/deployment.rb
        lib/bundler/gem_tasks.rb
        lib/bundler/vlad.rb
        lib/bundler/templates/gems.rb
      ]
      lib_files = ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb` : `git ls-files -z -- lib`
      lib_files = lib_files.split("\x0").grep(/\.rb$/) - exclusions
      lib_files.reject! {|f| f.start_with?("lib/bundler/vendor") }
      lib_files.map! {|f| f.chomp(".rb") }
      sys_exec!("ruby -w -Ilib") do |input, _, _|
        lib_files.each do |f|
          input.puts "require '#{f.sub(%r{\Alib/}, "")}'"
        end
      end

      expect(last_command.stdboth.split("\n")).to be_well_formed
    end
  end
end
