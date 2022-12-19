# Usage: ruby tool/update-NEWS-refs.rb

orig_src = File.read(File.join(__dir__, "../NEWS.md"))
lines = orig_src.lines(chomp: true)

links = {}
while lines.last =~ %r{\A\[(.*?)\]:\s+(?:.*)\z}
  links[$1] = lines.pop
end

if links.empty? || lines.last != ""
  raise "NEWS.md must end with a sequence of links"
end

new_src = lines.join("\n").gsub(/\[?\[((?:Feature|Bug)\s+#(\d+))\]\]?/) do
  links[$1] ||= "[#$1]: ".ljust(18) + "https://bugs.ruby-lang.org/issues/#$2"
  "[[#$1]]"
end.chomp + "\n\n"

redmine_links, non_redmine_links = links.partition {|k,| k =~ /\A(Feature|Bug)\s+#\d+\z/ }

redmine_links.sort_by {|k,| k[/\d+/].to_i }.each do |_k, v|
  new_src << v << "\n"
end

non_redmine_links.reverse_each do |_k, v|
  new_src << v << "\n"
end

if orig_src != new_src
  print "Update NEWS.md? [y/N]"
  $stdout.flush
  if gets.chomp == "y"
    File.write(File.join(__dir__, "../NEWS.md"), new_src)
  end
end
