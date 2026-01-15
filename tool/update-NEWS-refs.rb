# Usage: ruby tool/update-NEWS-refs.rb

orig_src = File.read(File.join(__dir__, "../NEWS.md"))
lines = orig_src.lines(chomp: true)

links = {}
while lines.last =~ %r{\A\[(.*?)\]:\s+(.*)\z}
  links[$1] = $2
  lines.pop
end

if links.empty? || lines.last != ""
  raise "NEWS.md must end with a sequence of links"
end

trackers = ["Feature", "Bug", "Misc"]
labels = links.keys.reject {|k| k.start_with?(*trackers)}
new_src = lines.join("\n").gsub(/\[?\[(#{Regexp.union(trackers)}\s+#(\d+))\]\]?/) do
  links[$1] ||= "https://bugs.ruby-lang.org/issues/#$2"
  "[[#$1]]"
end.gsub(/\[\[#{Regexp.union(labels)}\]\]?/) do
  "[#$1]"
end.chomp + "\n\n"

label_width = links.max_by {|k, _| k.size}.first.size + 4
redmine_links, non_redmine_links = links.partition {|k,| k =~ /\A#{Regexp.union(trackers)}\s+#\d+\z/ }

(redmine_links.sort_by {|k,| k[/\d+/].to_i } + non_redmine_links.reverse).each do |k, v|
  new_src << "[#{k}]:".ljust(label_width) << v << "\n"
end

if orig_src != new_src
  print "Update NEWS.md? [y/N]"
  $stdout.flush
  if gets.chomp == "y"
    File.write(File.join(__dir__, "../NEWS.md"), new_src)
  end
end
