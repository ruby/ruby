# -*- coding: us-ascii -*-

# Used to expand Ruby template files by common.mk, uncommon.mk and
# some Ruby extension libraries.

require 'erb'
require 'optparse'
require 'fileutils'
$:.unshift(File.dirname(__FILE__))
require 'vpath'

vpath = VPath.new
timestamp = nil
output = nil
ifchange = nil
source = false
color = nil

opt = OptionParser.new do |o|
  o.on('-t', '--timestamp[=PATH]') {|v| timestamp = v || true}
  o.on('-o', '--output=PATH') {|v| output = v}
  o.on('-c', '--[no-]if-change') {|v| ifchange = v}
  o.on('-x', '--source') {source = true}
  o.on('--color') {color = true}
  vpath.def_options(o)
  o.order!(ARGV)
end
unchanged = "unchanged"
updated = "updated"
if color or (color == nil && STDOUT.tty?)
  if (/\A\e\[.*m\z/ =~ IO.popen("tput smso", "r", err: IO::NULL, &:read) rescue nil)
    beg = "\e["
    colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:\n]*)/)] : {}
    reset = "#{beg}m"
    unchanged = "#{beg}#{colors["pass"] || "32;1"}m#{unchanged}#{reset}"
    updated = "#{beg}#{colors["fail"] || "31;1"}m#{updated}#{reset}"
  end
end
template = ARGV.shift or abort opt.to_s
erb = ERB.new(File.read(template), nil, '%-')
erb.filename = template
result = source ? erb.src : erb.result
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
