assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  ZZZ.ok
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  require "./zzz.rb"
  ZZZ.ok
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  proc{$SAFE=4; ZZZ.ok}.call
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  require "./zzz.rb"
  proc{$SAFE=4; ZZZ.ok}.call
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def hoge;:ok;end;end"}
  autoload :ZZZ, File.join(Dir.pwd, 'zzz.rb')
  module M; end
  Thread.new{M.instance_eval('$SAFE=4; ZZZ.new.hoge')}.value
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def hoge;:ok;end;end"}
  autoload :ZZZ, File.join(Dir.pwd, 'zzz.rb')
  module M; end
  Thread.new{$SAFE=4; M.instance_eval('ZZZ.new.hoge')}.value
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def hoge;:ok;end;end"}
  autoload :ZZZ, File.join(Dir.pwd, 'zzz.rb')
  Thread.new{$SAFE=4; eval('ZZZ.new.hoge')}.value
}

assert_equal 'ok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def hoge;:ok;end;end"}
  autoload :ZZZ, File.join(Dir.pwd, 'zzz.rb')
  module M; end
  Thread.new{eval('$SAFE=4; ZZZ.new.hoge')}.value
}

assert_equal 'okok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  t1 = Thread.new {ZZZ.ok}
  t2 = Thread.new {ZZZ.ok}
  [t1.value, t2.value].join
}

