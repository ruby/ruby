require 'rbconfig'
require 'timeout'
require 'fileutils'

github_actions = ENV["GITHUB_ACTIONS"] == "true"

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
dummy_rake_compiler_dir = File.realpath('../dummy-rake-compiler', __FILE__)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  next if ARGV.any? {|pat| !File.fnmatch?(pat, gem)}
  puts "#{github_actions ? "##[group]" : "\n"}Testing the #{gem} gem"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{rake} test"
  first_timeout = 600 # 10min

  if gem == "typeprof"
    rbs_build_dir = 'ext/-test-/gems/rbs'
    raise "need to run rbs test suite before typeprof" unless File.readable?("#{rbs_build_dir}/rbs_extension.#{RbConfig::CONFIG['DLEXT']}")
    ENV["RUBYLIB"] = ["#{gem_dir}/src/rbs/lib", ENV.fetch("RUBYLIB", nil)].compact.join(":")
  end

  if gem == "rbs"
    test_command << " stdlib_test validate"

    first_timeout *= 3

    # copied from debug gem
    build_dir = 'ext/-test-/gems/rbs'
    FileUtils.mkdir_p(build_dir)
    extconf_path = File.expand_path('../../gems/src/rbs/ext/rbs_extension/extconf.rb', __FILE__)
    system("#{ruby} -C #{build_dir} #{extconf_path}") or raise
    system("cd #{build_dir} && make extout=../../../../.ext libdir=../../../..") or raise
    ENV["RUBYLIB"] = [File.expand_path(dummy_rake_compiler_dir), File.expand_path(build_dir), ENV.fetch("RUBYLIB", nil)].compact.join(":")
  end

  if gem == "minitest"
    # Tentatively exclude some tests that conflict with error_highlight
    # https://github.com/seattlerb/minitest/pull/880
    test_command << " 'TESTOPTS=-e /test_stub_value_block_args_5__break_if_not_passed|test_no_method_error_on_unexpected_methods/'"
  end

  if gem == "debug"
    build_dir = 'ext/-test-/gems/debug'
    FileUtils.mkdir_p(build_dir)
    extconf_path = File.expand_path('../../gems/src/debug/ext/debug/extconf.rb', __FILE__)
    system("#{ruby} -C #{build_dir} #{extconf_path}") or raise
    system("cd #{build_dir} && make extout=../../../../.ext libdir=../../../..") or raise
    ENV["RUBYLIB"] = [File.expand_path(build_dir + "/.."), ENV.fetch("RUBYLIB", nil)].compact.join(":")
  end

  print "[command]" if github_actions
  puts test_command
  pid = Process.spawn(test_command, "#{/mingw|mswin/ =~ RUBY_PLATFORM ? 'new_' : ''}pgroup": true)
  {nil => first_timeout, INT: 30, TERM: 10, KILL: nil}.each do |sig, sec|
    if sig
      puts "Sending #{sig} signal"
      Process.kill("-#{sig}", pid)
    end
    begin
      break Timeout.timeout(sec) {Process.wait(pid)}
    rescue Timeout::Error
    end
  end

  unless $?.success?
    puts "Tests failed with exit code #{$?.exitstatus}"
    if allowed_failures.include?(gem)
      puts "Ignoring test failures for #{gem} due to \$TEST_BUNDLED_GEMS_ALLOW_FAILURES"
    else
      failed << gem
      exit_code = $?.exitstatus
    end
  end
  print "##[endgroup]\n" if github_actions
end

puts "Failed gems: #{failed.join(', ')}" unless failed.empty?
exit exit_code
