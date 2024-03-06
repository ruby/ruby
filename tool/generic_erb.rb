# -*- coding: us-ascii -*-

# Used to expand Ruby template files by common.mk, uncommon.mk and
# some Ruby extension libraries.

require 'erb'
require 'optparse'
require_relative 'lib/output'

out = Output.new
source = false
templates = []

ARGV.options do |o|
  o.on('-i', '--input=PATH') {|v| template << v}
  o.on('-x', '--source') {source = true}
  out.def_options(o)
  o.order!(ARGV)
  templates << (ARGV.shift or abort o.to_s) if templates.empty?
end

# Used in prelude.c.tmpl and unicode_norm_gen.tmpl
output = out.path
vpath = out.vpath

# A hack to prevent "unused variable" warnings
output, vpath = output, vpath

result = templates.map do |template|
  erb = ERB.new(File.read(template), trim_mode: '%-')
  erb.filename = template
  source ? erb.src : proc{erb.result(binding)}.call
end
result = result.size == 1 ? result[0] : result.join("")
out.write(result)
