#!/usr/bin/env ruby
require 'json'
news = File.read("NEWS.md")
prev = news[/since the \*+(\d+\.\d+\.\d+)\*+/, 1]
prevs = [prev, prev.sub(/\.\d+\z/, '')]

update = ->(list, type, desc = "updated") do
  item = ->(mark = "* ", sub_bullets = {}) do
    "### The following #{type} gem#{list.size == 1 ? ' is' : 's are'} #{desc}.\n\n" +
      list.map {|g, v|
        s = "#{mark}#{g} #{v}\n"
        s += sub_bullets[g].join("") if sub_bullets[g]
        s
      }.join("") + "\n"
  end
  news.sub!(/^(?:\*( +)|#+ *)?The following #{type} gems? (?:are|is) #{desc}\.\n+(?:(?:(?(1) \1)\*( *).*\n)(?:[ \t]+\*.*\n)*)*\n*/) do
    mark = "#{$1&.dup&.<< " "}*#{$2 || ' '}"
    # Parse existing sub-bullets from matched section
    sb = {}; cg = nil
    $~.to_s.each_line do |l|
      if l =~ /^\* ([A-Za-z0-9_\-]+)\s/
        cg = $1
      elsif cg && l =~ /^\s+\*/
        (sb[cg] ||= []) << l
      else
        cg = nil
      end
    end
    item[mark, sb]
  end or news.sub!(/^## Stdlib updates(?:\n+The following.*(?:\n+(?:( *\* *).*|[ \t]+\*.*))*)* *\n+\K/) do
    item[$1 || "* "]
  end
end

load_gems_json = ->(type) do
  JSON.parse(File.read("#{type}_gems.json"))['gems'].filter_map do |g|
    v = g['versions'].values_at(*prevs).compact.first
    g = g['gem']
    g = 'RubyGems' if g == 'rubygems'
    [g, v] if v
  end.to_h
end

ARGV.each do |type|
  last = load_gems_json[type]
  changed = File.foreach("gems/#{type}_gems").filter_map do |l|
    next if l.start_with?("#")
    g, v = l.split(" ", 3)
    next unless v
    [g, v] unless last[g] == v
  end
  changed, added = changed.partition {|g, _| last[g]}
  update[changed, type] or next
  if added and !added.empty?
    if type == 'bundled'
      default_gems = load_gems_json['default']
      promoted = {}
      added.delete_if do |k, v|
        default_gems.key?(k) && promoted[k] = v
      end
      update[added, type, 'added']
      update[promoted, type, 'promoted from default gems'] or next
    else
      update[added, type, 'added'] or next
    end
  end
  File.write("NEWS.md", news)
end
