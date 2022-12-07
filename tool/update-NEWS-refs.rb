# Usage: ruby tool/update-NEWS-refs.rb

orig_src = File.read(File.join(__dir__, "../NEWS.md"))
lines = orig_src.lines(chomp: true)

links = {}
while lines.last =~ %r{\A\[(?:Feature|Bug) #(\d+)\]:\s+https://bugs\.ruby-lang\.org/issues/\1\z}
  links[$1] = lines.pop
end

if links.empty? || lines.last != ""
  raise "NEWS.md must end with a sequence of links to bugs.ruby-lang.org like \"[Feature #XXXXX]: https://bugs.ruby-lang.org/issues/XXXXX\""
end

new_src = lines.join("\n").gsub(/\[?\[(Feature|Bug)\s+#(\d+)\]\]?/) do
  links[$2] ||= "[#$1 ##$2]: ".ljust(17) + "https://bugs.ruby-lang.org/issues/##$2"
  "[[#$1 ##$2]]"
end.chomp + "\n\n" + links.keys.sort.map {|k| links[k] }.join("\n") + "\n"

if orig_src != new_src
  print "Update NEWS.md? [y/N]"
  $stdout.flush
  if gets.chomp == "y"
    File.write(File.join(__dir__, "../NEWS.md"), new_src)
  end
end
