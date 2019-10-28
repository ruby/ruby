require 'rbconfig'

allowed_failures = ENV['TEST_BUNDLED_GEMS_ALLOW_FAILURES'] || ''
allowed_failures = allowed_failures.split(',').reject(&:empty?)

gem_dir = File.expand_path('../../gems', __FILE__)
exit_code = 0
File.foreach("#{gem_dir}/bundled_gems") do |line|
  gem = line.split.first
  puts "\nTesting the #{gem} gem"

  gem_src_dir = File.expand_path("#{gem_dir}/src/#{gem}", __FILE__)
  test_command = "#{ARGV.join(' ')} -C #{gem_src_dir} -Ilib ../../../.bundle/bin/rake"
  puts test_command
  system test_command

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
