###
# Converts the probes.d file to redmine wiki format. Usage:
#
#   ruby tool/probes_to_wiki.rb probes.d

File.read(ARGV[0]).scan(/\/\*.*?\*\//m).grep(/ruby/) do |comment|
  comment.gsub!(/^(\/\*|[ ]*)|\*\/$/, '').strip!
  puts
  comment.each_line.with_index do |line, i|
    if i == 0
      puts "=== #{line.chomp}"
    else
      puts line.gsub(/`([^`]*)`/, '(({\1}))')
    end
  end
end
