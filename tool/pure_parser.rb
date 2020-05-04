#!/usr/bin/ruby -pi
BEGIN {
  require_relative 'lib/colorize'

  colorize = Colorize.new
  file = ARGV.shift
  begin
    version = IO.popen(ARGV+%w[--version], &:read)
  rescue Errno::ENOENT
    abort "Failed to run `#{colorize.fail ARGV.join(' ')}'; You may have to install it."
  end
  unless /\Abison .* (\d+)\.\d+/ =~ version
    puts colorize.fail("not bison")
    exit
  end
  exit if $1.to_i >= 3
  ARGV.clear
  ARGV.push(file)
}
$_.sub!(/^%define\s+api\.pure/, '%pure-parser')
$_.sub!(/^%define\s+.*/, '')
