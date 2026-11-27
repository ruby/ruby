code = [+""]
source = File.read(ARGV.shift)
source.scan(/^\w+,\s*\KVK_\w+/) do |n|
  puts("#ifndef #{n}\n# define #{n} UNDEFINED_VK\n#endif")
  code << +"" if n.size + code.last.size > 60
  code.last << " x(#{n})z"
end
puts ["#define EACH_VK(x,z)", code].join(" \\\n    "), ""
IO.popen(["gperf", *ARGV], "r+") do |f|
  w = Thread.start {
    f.puts source
    f.close_write
  }
  puts f.read.sub(/^\w*hash .*\{(?m:.*?)\n\}/) {
    $&.sub!(" hval = ", " hval = (unsigned int)")
  }
  w.join
end
