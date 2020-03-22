# frozen_string_literal: true
# This is a script to run a command in ARGV, expanding tabs in some files
# included by vm.c to normalize indentation of MJIT header.
#
# Note that preprocessor of GCC converts a hard tab to one spaces, where
# we expect it to be shown as 8 spaces. To obviate this script, we need
# to convert all tabs to spaces in these files.

require 'fileutils'

srcdir = File.expand_path('..', __dir__)
targets = Dir.glob(File.join(srcdir, 'vm*.*'))
sources = {}
mtimes = {}

targets.each do |target|
  sources[target] = File.read(target)
  mtimes[target] = File.mtime(target)

  expanded = sources[target].gsub(/^\t+/) { |tab| ' ' * 8 * tab.length }
  if sources[target] == expanded
    puts "#{target.dump} has no hard tab indentation. This should be ignored in tool/run_without_tabs.rb."
  end
  File.write(target, expanded)
  FileUtils.touch(target, mtime: mtimes[target])
end

result = system(*ARGV)

targets.each do |target|
  File.write(target, sources.fetch(target))
  FileUtils.touch(target, mtime: mtimes.fetch(target))
end

exit result
