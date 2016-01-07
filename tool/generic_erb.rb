# -*- coding: us-ascii -*-

# Used to expand Ruby template files by common.mk, uncommon.mk and
# some Ruby extension libraries.

require 'erb'
require 'optparse'
require_relative 'lib/vpath'
require_relative 'lib/atomic_write'

vpath = VPath.new
aw = AtomicWrite.new
aw.vpath = vpath
source = false
templates = []

ARGV.options do |o|
  o.on('-i', '--input=PATH') {|v| template << v}
  o.on('-x', '--source') {source = true}
  aw.def_options(o)
  vpath.def_options(o)
  o.order!(ARGV)
  templates << (ARGV.shift or abort o.to_s) if templates.empty?
end

result = templates.map do |template|
  if ERB.instance_method(:initialize).parameters.assoc(:key) # Ruby 2.6+
    erb = ERB.new(File.read(template), trim_mode: '%-')
  else
    erb = ERB.new(File.read(template), nil, '%-')
  end
  erb.filename = template
  source ? erb.src : proc{erb.result(binding)}.call
end
result = result.size == 1 ? result[0] : result.join("")
aw.emit(result)
