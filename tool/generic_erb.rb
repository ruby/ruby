# -*- coding: us-ascii -*-

# Used to expand Ruby template files by common.mk, uncommon.mk and
# some Ruby extension libraries.

require 'erb'
require 'optparse'
require 'fileutils'
$:.unshift(File.dirname(__FILE__))
require 'vpath'
require 'colorize'

vpath = VPath.new
timestamp = nil
output = nil
ifchange = nil
source = false
color = nil
templates = []

ARGV.options do |o|
  o.on('-t', '--timestamp[=PATH]') {|v| timestamp = v || true}
  o.on('-i', '--input=PATH') {|v| template << v}
  o.on('-o', '--output=PATH') {|v| output = v}
  o.on('-c', '--[no-]if-change') {|v| ifchange = v}
  o.on('-x', '--source') {source = true}
  o.on('--color') {color = true}
  vpath.def_options(o)
  o.order!(ARGV)
  templates << (ARGV.shift or abort o.to_s) if templates.empty?
end
color = Colorize.new(color)
unchanged = color.pass("unchanged")
updated = color.fail("updated")

result = templates.map do |template|
  erb = ERB.new(File.read(template), nil, '%-')
  erb.filename = template
  source ? erb.src : proc{erb.result(binding)}.call
end
result = result.size == 1 ? result[0] : result.join("")
if output
  if ifchange and (vpath.open(output, "rb") {|f| f.read} rescue nil) == result
    puts "#{output} #{unchanged}"
  else
    open(output, "wb") {|f| f.print result}
    puts "#{output} #{updated}"
  end
  if timestamp
    if timestamp == true
      dir, base = File.split(output)
      timestamp = File.join(dir, ".time." + base)
    end
    FileUtils.touch(timestamp)
  end
else
  print result
end
