#!/usr/bin/env ruby

require "fileutils"

test_lib_files = [
  ["lib/core_assertions.rb", "test/lib"],
  ["lib/find_executable.rb", "test/lib"],
  ["lib/envutil.rb", "test/lib"],
  ["lib/helper.rb", "test/lib"],
  ["rakelib/sync_tool.rake", "rakelib"],
].map do |file, dest|
  [file, dest, File.read("#{__dir__}/#{file}")]
end

repos = %w[
  bigdecimal cgi cmath date delegate did_you_mean digest drb erb etc
  fileutils find forwardable io-console io-nonblock io-wait ipaddr
  irb logger net-http net-protocol open-uri open3 openssl optparse
  ostruct pathname pstore psych racc resolv stringio strscan tempfile
  time timeout tmpdir uri weakref win32ole yaml zlib
]

branch_name = "update-test-lib-#{Time.now.strftime("%Y%m%d")}"
title = "Update test libraries from ruby/ruby #{Time.now.strftime("%Y-%m-%d")}"
commit = `git rev-parse HEAD`.chomp
message = "From https://github.com/ruby/ruby/commit/#{commit}"

update = true
keep = nil
topdir = nil
while arg = ARGV.shift
  case arg
  when '--dry-run'
    update = false
    keep = true
  when '--update'
    update = true
    keep = false if keep.nil?
  when '--no-update'
    update = false
    keep = true if keep.nil?
  when '--keep'
    keep = true
  when '--no-keep'
    keep = false
  when '--'
    break
  else
    if topdir
      ARGV.unshift(arg)
    else
      topdir = arg
    end
    break
  end
end
topdir ||= '..'
repos = ARGV unless ARGV.empty?

repos.each do |repo|
  puts "#{repo}: start"

  Dir.chdir("#{topdir}/#{repo}") do
    if `git branch --list #{branch_name}`.empty?
      system(*%W"git switch master")
      system(*%W"git switch -c #{branch_name}")
    else
      puts "#{repo}: skip"
      next
    end

    test_lib_files.each do |file, dest, code|
      FileUtils.mkdir_p(dest)
      file = "#{dest}/#{File.basename(file)}"
      File.binwrite(file, code)
      system "git add #{file}"
    end

    rf = File.binread("Rakefile")
    if rf.sub!(/(?>\A|(\n)\n*)task +:sync_tool +do\n(?>(?> .*)?\n)*end\n(?=\z|(\n))/) {$1&&$2}
      File.binwrite("Rakefile", rf)
      system "git add Rakefile"
    end

    if IO.popen(%W"git commit -m #{title}\n\n#{message}", &:read).chomp =~ /nothing to commit/
      puts "#{repo}: nothing to update"
    elsif update
      system(*%W"git push")
      system(*%W"gh repo set-default ruby/#{repo}")
      system(*%W"gh pr create --base master --head ruby:#{branch_name} --title #{title} --body #{message}")
      puts "#{repo}: updated"
    end

    unless keep
      system "git switch master"
      system "git branch -D #{branch_name}"
    end
  end
rescue StandardError => e
  puts e
end
