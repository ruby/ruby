#!/usr/bin/ruby
require 'json'
news = File.read("NEWS.md")
prev = news[/since the \*+(\d+\.\d+\.\d+)\*+/, 1]
prevs = [prev, prev.sub(/\.\d+\z/, '')]

update = ->(list, type, desc = "updated") do
  news.sub!(/^(?:\*( +))?The following #{type} gems? (?:are|is) #{desc}\.\n(\n*)\K(?:(?(1) \1)\*( +).*\n)*\n*/) do
    mark = "#{$1&.<< " "}*#{$3 || ' '}"
    list.map {|g, v|"#{mark}#{g} #{v}\n"}.join("") + $2
  end
end
ARGV.each do |type|
  last = JSON.parse(File.read("#{type}_gems.json"))['gems'].filter_map do |g|
    v = g['versions'].values_at(*prevs).compact.first
    g = g['gem']
    g = 'RubyGems' if g == 'rubygems'
    [g, v] if v
  end.to_h
  changed = File.foreach("gems/#{type}_gems").filter_map do |l|
    next if l.start_with?("#")
    g, v = l.split(" ", 3)
    next unless v
    [g, v] unless last[g] == v
  end
  if type == 'bundled'
    changed, added = changed.partition {|g, _| last[g]}
  end
  update[changed, type] or next
  if added and !added.empty?
    update[added, 'default', 'now bundled gems'] or next
  end
  File.write("NEWS.md", news)
end
