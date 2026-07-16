#!/usr/bin/env ruby

required_ruby_version = Gem::Version.new("3.4.0")
raise "Ruby version #{required_ruby_version} or higher is required" if Gem::Version.new(RUBY_VERSION) < required_ruby_version

PERF_MAP = ARGV[0] || raise("Expected perf map as first argument")

sizes = Hash.new(0)
counts = Hash.new(0)
File.foreach(PERF_MAP) do |line|
  address, size, name = line.split(" ", 3)
  name.delete_prefix!("ZJIT: ")
  name.delete_suffix!("\n")
  sizes[name] += size.to_i(16)
  counts[name] += 1
end

total_size = sizes.values.sum

def pretty_size bytes
  u = 0
  s = 1024
  while bytes >= s || -bytes >= s
    bytes /= s.to_f
    u += 1
  end
  "#{bytes.round(1)} #{'​KMGTPEZY'[u]}B"
end

n = 20

sizes.sort_by { |name, size| -size }.first(n).each do |name, size|
  puts "#{pretty_size(size)} total (#{(size/total_size.to_f*100).round(1)}%); #{pretty_size(size/counts[name].to_f)} each #{name}"
end

puts

counts.sort_by { |name, count| -count }.first(n).each do |name, count|
  puts "#{count} #{name}"
end
