require 'rbconfig'
require 'timeout'
require 'fileutils'
require_relative 'lib/colorize'

ENV.delete("GNUMAKEFLAGS")

github_actions = ENV["GITHUB_ACTIONS"] == "true"

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

ENV["GEM_PATH"] = [File.realpath('.bundle'), File.realpath('../.bundle', __dir__)].join(File::PATH_SEPARATOR)

colorize = Colorize.new
rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
rubylib = [gem_dir+'/lib', ENV["RUBYLIB"]].compact.join(File::PATH_SEPARATOR)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  next if ARGV.any? {|pat| !File.fnmatch?(pat, gem)}
  # 93(bright yellow) is copied from .github/workflows/mingw.yml
  puts "#{github_actions ? "::group::\e\[93m" : "\n"}Testing the #{gem} gem#{github_actions ? "\e\[m" : ""}"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} #{rake} test"
  first_timeout = 600 # 10min

  toplib = gem
  case gem
  when "typeprof"

  when "rbs"
    # TODO: We should skip test file instead of test class/methods
    skip_test_files = %w[
    ]

    skip_test_files.each do |file|
      path = "#{gem_dir}/src/#{gem}/#{file}"
      File.unlink(path) if File.exist?(path)
    end

    test_command << " stdlib_test validate RBS_SKIP_TESTS=#{__dir__}/rbs_skip_tests SKIP_RBS_VALIDATION=true"
    first_timeout *= 3

  when "debug"
    # Since debug gem requires debug.so in child processes without
    # activating the gem, we preset necessary paths in RUBYLIB
    # environment variable.
    load_path = true

  when "test-unit"
    test_command = "#{ruby} -C #{gem_dir}/src/#{gem} test/run-test.rb"

  when /\Anet-/
    toplib = gem.tr("-", "/")

  end

  if load_path
    libs = IO.popen([ruby, "-e", "old = $:.dup; require '#{toplib}'; puts $:-old"], &:read)
    next unless $?.success?
    puts libs
    ENV["RUBYLIB"] = [libs.split("\n"), rubylib].join(File::PATH_SEPARATOR)
  else
    ENV["RUBYLIB"] = rubylib
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
  rescue Interrupt
    exit_code = Signal.list["INT"]
    Process.kill("-KILL", pid)
    Process.wait(pid)
    break
  end

  print "::endgroup::\n" if github_actions
  unless $?.success?

    mesg = "Tests failed " +
           ($?.signaled? ? "by SIG#{Signal.signame($?.termsig)}" :
              "with exit code #{$?.exitstatus}")
    puts colorize.decorate(mesg, "fail")
    if allowed_failures.include?(gem)
      mesg = "Ignoring test failures for #{gem} due to \$TEST_BUNDLED_GEMS_ALLOW_FAILURES"
      puts colorize.decorate(mesg, "skip")
    else
      failed << gem
      exit_code = $?.exitstatus if $?.exitstatus
    end
  end
end

puts "Failed gems: #{failed.join(', ')}" unless failed.empty?
exit exit_code
