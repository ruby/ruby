code = [+""]
ARGF.read.scan(/^\w+,\s*\KVK_\w+/) do |n|
  puts("#ifndef #{n}\n# define #{n} UNDEFINED_VK\n#endif")
  code << +"" if n.size + code.last.size > 60
  code.last << " x(#{n})z"
end
puts ["#define EACH_VK(x,z)", code].join(" \\\n    "), ""
