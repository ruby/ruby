#!/usr/bin/env ruby

RESULT = / *    #(.*?)/
CODE = / *    (.*?)/

ARGV.each do |path|
  lines = File.readlines(path)

  lines.each do |line|
    if line =~ /\/\*/
      last = nil
    elsif match = line.match(RESULT)
      line.replace(" *    \# => #{last}")
    elsif match = line.match(CODE)
      last = eval(match[1])
    end
  end

  puts lines
end
