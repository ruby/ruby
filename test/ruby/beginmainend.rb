BEGIN {
  puts "begin1"
  local_begin1 = "local_begin1"
  $global_begin1 = "global_begin1"
  ConstBegin1 = "ConstBegin1"
}

BEGIN {
  puts "begin2"
}

# for scope check
raise if defined?(local_begin1)
raise unless defined?($global_begin1)
raise unless defined?(::ConstBegin1)
local_for_end2 = "end2"
$global_for_end1 = "end1"

puts "main"

END {
  puts local_for_end2
}

END {
  raise
  puts "should not be dumped"
}

eval <<EOE
  BEGIN {
    puts "innerbegin1"
  }

  BEGIN {
    puts "innerbegin2"
  }

  END {
    puts "innerend2"
  }

  END {
    puts "innerend1"
  }
EOE

END {
  exit
  puts "should not be dumped"
}

END {
  puts $global_for_end1
}
