require 'rbconfig'
require 'timeout'

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

rake = File.realpath("../../.bundle/bin/rake", __FILE__)
gem_dir = File.realpath('../../gems', __FILE__)
exit_code = 0
ruby = ENV['RUBY'] || RbConfig.ruby
File.foreach("#{gem_dir}/bundled_gems") do |line|
  next if /^\s*(?:#|$)/ =~ line
  gem = line.split.first
  puts "\nTesting the #{gem} gem"

  test_command = "#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{rake}"

  if gem == "rbs"
    racc = File.realpath("../../libexec/racc", __FILE__)
    Process.spawn("#{ruby} -C #{gem_dir}/src/#{gem} -Ilib #{racc} -v -o lib/rbs/parser.rb lib/rbs/parser.y")
    test_command << " test"
  end

  puts test_command
  pid = Process.spawn(test_command, "#{/mingw|mswin/ =~ RUBY_PLATFORM ? 'new_' : ''}pgroup": true)
  {nil => 60, INT: 30, TERM: 10, KILL: nil}.each do |sig, sec|
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
      exit_code = $?.exitstatus
    end
  end
end

exit exit_code
