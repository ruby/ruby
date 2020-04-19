require "timeout"

CommandResults = {}

def run_commands(label, *commands, dir:)
  results = []

  commands.each do |command|
    puts command

    pid = Process.spawn(command, "#{/mingw|mswin/ =~ RUBY_PLATFORM ? 'new_' : ''}pgroup": true, chdir: dir)

    {nil => 120, INT: 30, TERM: 10, KILL: nil}.each do |sig, sec|
      if sig
        puts "Sending #{sig} signal"
        Process.kill("-#{sig}", pid)
      end
      begin
        break Timeout.timeout(sec) {Process.wait(pid)}
      rescue Timeout::Error
      end
    end

    results << [command, $?.success?, $?.exitstatus]

    unless $?.success?
      return
    end
  end
ensure
  CommandResults[label] = results
end

gem_dir = File.realpath('../../gems', __FILE__)

Dir.each_child(gem_dir) do |dir|
  dir = File.join(gem_dir, dir)

  unless Dir.glob("*.gemspec", base: dir).empty?
    gem_name = File.basename(dir)

    puts "Testing the #{gem_name} gem..."
    run_commands(gem_name, "bin/setup", "bin/test", dir: dir)
  end
end

failed = 0

CommandResults.each do |label, results|
  puts "#{label}:"

  results.each do |command, _, status|
    puts "  #{command} => #{status}"

    failed += 1 if status != 0
  end
end

exit 1 if failed > 0
