#!/usr/bin/ruby -pi
BEGIN {
  require_relative 'colorize'

  colorize = Colorize.new
  file = ARGV.shift
  unless /\Abison .* (\d+)\.\d+/ =~ IO.popen(ARGV+%w[--version], &:read)
    puts colorize.fail("not bison")
    exit
  end
  exit if $1.to_i >= 3
  ARGV.clear
  ARGV.push(file)
}
$_.sub!(/^%define\s+api\.pure/, '%pure-parser')
