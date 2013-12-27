STDOUT.binmode
ARGF.each do |line|
  line.gsub!(/@([a-z_]\w*)@/i) {
    (RbConfig::MAKEFILE_CONFIG[$1] or "").gsub(/\$\((.+?)\)/, %Q[${\\1}])
  }
  puts line
end
