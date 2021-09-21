require 'rbconfig'
require 'timeout'
require "fileutils"
require "shellwords"
require "optparse"

def run(*command, wait: true, raise_on_error: true, new_pgroup: false)
  if command.size == 1
    command = command[0]
  else
    command = Shellwords.join(command)
  end

  puts(">> #{command}")
  pid = Process.spawn(
    command,
    "#{/mingw|mswin/ =~ RUBY_PLATFORM ? 'new_' : ''}pgroup": new_pgroup
  )

  if wait
    pid, status = Process.waitpid2(pid)
    if raise_on_error
      raise "Command failed: #{command}" unless status.success?
    else
      status
    end
  else
    pid
  end
end

extout = File.join(Dir.pwd, ".ext")

OptionParser.new do |opts|
  opts.on("--extout=EXTOUT") do |path|
    extout = File.join(Dir.pwd, path)
  end
end.parse!(ARGV)

github_actions = ENV["GITHUB_ACTIONS"] == "true"

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

root = File.realpath("../../", __FILE__)
rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []
gem_ruby_stub = File.realpath("../gem_ruby_stub.rb", __FILE__)

File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  next if ARGV.any? {|pat| !File.fnmatch?(pat, gem)}
  puts "#{github_actions ? "##[group]" : "\n"}Testing the #{gem} gem"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{rake} test"
  first_timeout = 600 # 10min

  if gem == "typeprof"
    if Dir.glob("#{gem_dir}/src/rbs/ext/rbs_extension/rbs_extension.{bundle,so,dll}").empty?
      raise "need to run rbs test suite before typeprof"
    end
    ENV["RUBYLIB"] = [
      "#{gem_dir}/src/rbs/lib",
      "#{gem_dir}/src/rbs/ext/rbs_extension",
      ENV.fetch("RUBYLIB", nil)
    ].compact.join(":")
  end

  if gem == "rbs"
    run(ruby, "-C#{gem_dir}/src/#{gem}/ext/rbs_extension", "-Ilib", "extconf.rb")
    run("make", "-C#{gem_dir}/src/#{gem}/ext/rbs_extension", "extout=#{extout}")
    run("ls", "#{gem_dir}/src/#{gem}/ext/rbs_extension")

    ENV["RUBYLIB"] = [
      "#{gem_dir}/src/rbs/lib",
      "#{gem_dir}/src/rbs/ext/rbs_extension",
      "#{root}/tool",
      ENV.fetch("RUBYLIB", nil)
    ].compact.join(":")
    test_command = "#{ruby} -C #{gem_dir}/src/#{gem} #{rake} test stdlib_test validate"

    first_timeout *= 3
  end

  if gem == "minitest"
    # Tentatively exclude some tests that conflict with error_highlight
    # https://github.com/seattlerb/minitest/pull/880
    test_command << " 'TESTOPTS=-e /test_stub_value_block_args_5__break_if_not_passed|test_no_method_error_on_unexpected_methods/'"
  end

  print "[command]" if github_actions

  pid = run(test_command, new_pgroup: true, wait: false)
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
