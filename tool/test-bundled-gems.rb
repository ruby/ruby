require 'rbconfig'
require 'timeout'
require 'fileutils'
require 'shellwords'
require 'etc'
require_relative 'lib/colorize'
require_relative 'lib/gem_env'
require_relative 'lib/test/jobserver'

ENV.delete("GNUMAKEFLAGS")

github_actions = ENV["GITHUB_ACTIONS"] == "true"

DEFAULT_ALLOWED_FAILURES = RUBY_PLATFORM =~ /mswin|mingw/ ? [
  'debug',
  'irb',
  'csv',
] : []
allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').concat(DEFAULT_ALLOWED_FAILURES).uniq.reject(&:empty?)

# make test-bundled-gems BUNDLED_GEMS=gem1,gem2,gem3
bundled_gems = nil if (bundled_gems = ARGV.first&.split(","))&.empty?

colorize = Colorize.new
rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
rubylib = [gem_dir+'/lib', ENV["RUBYLIB"]].compact.join(File::PATH_SEPARATOR)
run_opts = ENV["RUN_OPTS"]&.shellsplit
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []

max = ENV['TEST_BUNDLED_GEMS_NPROCS']&.to_i || [Etc.nprocessors, 8].min
nprocs = Test::JobServer.max_jobs(max) || max
nprocs = 1 if nprocs < 1

if /mingw|mswin/ =~ RUBY_PLATFORM
  spawn_group = :new_pgroup
  signal_prefix = ""
else
  spawn_group = :pgroup
  signal_prefix = "-"
end

jobs = []
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next unless gem = line[/^[^\s\#]+/]
  next if bundled_gems&.none? {|pat| File.fnmatch?(pat, gem)}
  next unless File.directory?("#{gem_dir}/src/#{gem}/test")

  test_command = [ruby, *run_opts, "-C", "#{gem_dir}/src/#{gem}", rake, "test"]
  first_timeout = 600 # 10min
  env_rubylib = rubylib

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

    rbs_skip_tests = [
      File.join(__dir__, "/rbs_skip_tests")
    ]

    if /mswin|mingw/ =~ RUBY_PLATFORM
      rbs_skip_tests << File.join(__dir__, "/rbs_skip_tests_windows")
    end

    test_command.concat %W[stdlib_test validate RBS_SKIP_TESTS=#{rbs_skip_tests.join(File::PATH_SEPARATOR)} SKIP_RBS_VALIDATION=true]
    first_timeout *= 3

  when "debug"
    # Since debug gem requires debug.so in child processes without
    # activating the gem, we preset necessary paths in RUBYLIB
    # environment variable.
    libs = IO.popen([ruby, "-e", "old = $:.dup; require '#{toplib}'; puts $:-old"], &:read)
    next unless $?.success?
    env_rubylib = [libs.split("\n"), rubylib].join(File::PATH_SEPARATOR)

  when "test-unit"
    test_command = [ruby, *run_opts, "-C", "#{gem_dir}/src/#{gem}", "test/run.rb"]

  when "csv"
    first_timeout = 30

  when "win32ole"
    next unless /mswin|mingw/ =~ RUBY_PLATFORM

  end

  jobs << {
    gem: gem,
    test_command: test_command,
    first_timeout: first_timeout,
    rubylib: env_rubylib,
  }
end

running_pids = []
interrupted = false

trap(:INT) do
  interrupted = true
  running_pids.each do |pid|
    Process.kill("#{signal_prefix}INT", pid) rescue nil
  end
end

results = Array.new(jobs.size)
queue = Queue.new
jobs.each_with_index { |j, i| queue << [j, i] }
nprocs.times { queue << nil }
print_queue = Queue.new

puts "Running #{jobs.size} gem tests with #{nprocs} workers..."

printer = Thread.new do
  printed = 0
  while printed < jobs.size
    result = print_queue.pop
    break if result.nil?

    gem = result[:gem]
    elapsed = result[:elapsed]
    status = result[:status]
    t = " in %.6f sec" % elapsed

    print (github_actions ? "::group::" : "\n")
    puts colorize.decorate("Testing the #{gem} gem", "note")
    print "[command]" if github_actions
    p result[:test_command]
    result[:log_lines].each { |l| puts l }
    print result[:output]
    print "::endgroup::\n" if github_actions

    if status&.success?
      puts colorize.decorate("Test passed#{t}", "pass")
    else
      mesg = "Tests failed " +
             (status&.signaled? ? "by SIG#{Signal.signame(status.termsig)}" :
                "with exit code #{status&.exitstatus}") + t
      puts colorize.decorate(mesg, "fail")
      if allowed_failures.include?(gem)
        mesg = "Ignoring test failures for #{gem} due to \$TEST_BUNDLED_GEMS_ALLOW_FAILURES or DEFAULT_ALLOWED_FAILURES"
        puts colorize.decorate(mesg, "skip")
      else
        failed << gem
        exit_code = 1
      end
    end

    printed += 1
  end
end

threads = nprocs.times.map do
  Thread.new do
    while (item = queue.pop)
      break if interrupted
      job, index = item

      start_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      rd, wr = IO.pipe
      env = { "RUBYLIB" => job[:rubylib] }
      pid = Process.spawn(env, *job[:test_command], spawn_group => true, [:out, :err] => wr)
      wr.close
      running_pids << pid
      output_thread = Thread.new { rd.read }

      timeouts = { nil => job[:first_timeout], INT: 30, TERM: 10, KILL: nil }
      if /mingw|mswin/ =~ RUBY_PLATFORM
        timeouts.delete(:TERM)
      end

      log_lines = []
      status = nil
      timeouts.each do |sig, sec|
        if sig
          log_lines << "Sending #{sig} signal"
          begin
            Process.kill("#{signal_prefix}#{sig}", pid)
          rescue Errno::ESRCH
            _, status = Process.wait2(pid) unless status
            break
          end
        end
        begin
          break Timeout.timeout(sec) { _, status = Process.wait2(pid) }
        rescue Timeout::Error
        end
      end

      captured = output_thread.value
      rd.close
      running_pids.delete(pid)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_at

      result = {
        gem: job[:gem],
        test_command: job[:test_command],
        status: status,
        elapsed: elapsed,
        output: captured,
        log_lines: log_lines,
      }
      results[index] = result
      print_queue << result
    end
  end
end

threads.each(&:join)
print_queue << nil
printer.join

if interrupted
  exit Signal.list["INT"]
end

unless failed.empty?
  puts "\n#{colorize.decorate("Failed gems: #{failed.join(', ')}", "fail")}"
  results.compact.each do |result|
    next if result[:status]&.success?
    next if allowed_failures.include?(result[:gem])
    puts colorize.decorate("\nTesting the #{result[:gem]} gem", "note")
    print result[:output]
  end
end
exit exit_code
