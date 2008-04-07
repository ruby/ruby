assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  print ZZZ.ok
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  require "./zzz.rb"
  print ZZZ.ok
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  print proc{$SAFE=4; ZZZ.ok}.call
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  require "./zzz.rb"
  print proc{$SAFE=4; ZZZ.ok}.call
}
