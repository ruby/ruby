require 'rbconfig'
require 'timeout'

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
failed = []
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  next if ARGV.any? {|pat| !File.fnmatch?(pat, gem)}
  puts "\nTesting the #{gem} gem"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{rake} test"
  first_timeout = 600 # 10min

  if gem == "rbs"
    racc = File.realpath("../../libexec/racc", __FILE__)
    pid = Process.spawn("#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{racc} -v -o lib/rbs/parser.rb lib/rbs/parser.y")
    Process.waitpid(pid)
    test_command << " stdlib_test validate"

    first_timeout *= 3
  end

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
end

puts "Failed gems: #{failed.join(', ')}" unless failed.empty?
exit exit_code
