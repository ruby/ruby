require 'rbconfig'
require 'timeout'
require 'fileutils'
require_relative 'lib/colorize'
require_relative 'lib/gem_env'

ENV.delete("GNUMAKEFLAGS")

github_actions = ENV["GITHUB_ACTIONS"] == "true"

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
if RUBY_PLATFORM =~ /mswin|mingw/
  allowed_failures = [allowed_failures, "rbs,debug,irb,power_assert"].join(',')
end
allowed_failures = allowed_failures.split(',').uniq.reject(&:empty?)

# make test-bundled-gems BUNDLED_GEMS=gem1,gem2,gem3
bundled_gems = ARGV.first || ''

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
  next unless bundled_gems.empty? || bundled_gems.split(",").include?(gem)
  next unless File.directory?("#{gem_dir}/src/#{gem}/test")

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} #{rake} test"
  first_timeout = 600 # 10min

  toplib = gem
  unless File.exist?("#{gem_dir}/src/#{gem}/lib/#{toplib}.rb")
    toplib = gem.tr("-", "/")
    next unless File.exist?("#{gem_dir}/src/#{gem}/lib/#{toplib}.rb")
  end

  case gem
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
    test_command = "#{ruby} -C #{gem_dir}/src/#{gem} test/run.rb"

  when "win32ole"
    next unless /mswin|mingw/ =~ RUBY_PLATFORM

  end

  if load_path
    libs = IO.popen([ruby, "-e", "old = $:.dup; require '#{toplib}'; puts $:-old"], &:read)
    next unless $?.success?
    ENV["RUBYLIB"] = [libs.split("\n"), rubylib].join(File::PATH_SEPARATOR)
  else
    ENV["RUBYLIB"] = rubylib
  end

  # 93(bright yellow) is copied from .github/workflows/mingw.yml
  puts "#{github_actions ? "::group::\e\[93m" : "\n"}Testing the #{gem} gem#{github_actions ? "\e\[m" : ""}"
  print "[command]" if github_actions
  puts test_command
  timeouts = {nil => first_timeout, INT: 30, TERM: 10, KILL: nil}
  if /mingw|mswin/ =~ RUBY_PLATFORM
    timeouts.delete(:TERM)      # Inner process signal on Windows
    timeouts.delete(:INT)       # root process will be terminated too
    group = :new_pgroup
    pg = ""
  else
    group = :pgroup
    pg = "-"
  end
  pid = Process.spawn(test_command, group => true)
  timeouts.each do |sig, sec|
    if sig
      puts "Sending #{sig} signal"
      Process.kill("#{pg}#{sig}", pid)
    end
    begin
      break Timeout.timeout(sec) {Process.wait(pid)}
    rescue Timeout::Error
    end
  rescue Interrupt
    exit_code = Signal.list["INT"]
    Process.kill("#{pg}KILL", pid)
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
