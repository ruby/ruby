str = ARGF.gets
if /ChangeLog (\d+)/ =~ str
  puts %Q{char *rev = "#{$1}";}
else
  raise
end

if /ChangeLog \d+ ([\d-]+)/ =~ str
  puts %Q{char *date = "#{$1}";}
else
  raise
end

