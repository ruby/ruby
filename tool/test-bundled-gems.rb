require 'rbconfig'
require 'timeout'
require 'fileutils'

ENV.delete("GNUMAKEFLAGS")

github_actions = ENV["GITHUB_ACTIONS"] == "true"

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

ENV["GEM_PATH"] = [File.realpath('.bundle'), File.realpath('../.bundle', __dir__)].join(File::PATH_SEPARATOR)

rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
dummy_rake_compiler_dir = File.realpath('../dummy-rake-compiler', __FILE__)
rubylib = [File.expand_path(dummy_rake_compiler_dir), ENV["RUBYLIB"]].compact.join(File::PATH_SEPARATOR)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  next if ARGV.any? {|pat| !File.fnmatch?(pat, gem)}
  puts "#{github_actions ? "##[group]" : "\n"}Testing the #{gem} gem"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} #{rake} test"
  first_timeout = 600 # 10min

  toplib = gem
  case gem
  when "typeprof"

  when "rbs"
    test_command << " stdlib_test validate"
    first_timeout *= 3

  when "minitest"
    # Tentatively exclude some tests that conflict with error_highlight
    # https://github.com/seattlerb/minitest/pull/880
    test_command << " 'TESTOPTS=-e /test_stub_value_block_args_5__break_if_not_passed|test_no_method_error_on_unexpected_methods/'"

  when "debug"
    # Since debug gem requires debug.so in child processes without
    # acitvating the gem, we preset necessary paths in RUBYLIB
    # environment variable.
    load_path = true

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

  unless $?.success?

    puts "Tests failed " +
         ($?.signaled? ? "by SIG#{Signal.signame($?.termsig)}" :
            "with exit code #{$?.exitstatus}")
    if allowed_failures.include?(gem)
      puts "Ignoring test failures for #{gem} due to \$TEST_BUNDLED_GEMS_ALLOW_FAILURES"
    else
      failed << gem
      exit_code = $?.exitstatus if $?.exitstatus
    end
  end
  print "##[endgroup]\n" if github_actions
end

puts "Failed gems: #{failed.join(', ')}" unless failed.empty?
exit exit_code
