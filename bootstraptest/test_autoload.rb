assert_equal 'ok', %q{
  File.unlink('zzz.rb') if File.file?('zzz.rb')
  instance_eval do
    autoload :ZZZ, './zzz.rb'
    begin
      ZZZ
    rescue LoadError
      :ok
    end
  end
}, '[ruby-dev:43816]'

assert_equal 'ok', %q{
  open('zzz.rb', 'w') {|f| f.puts '' }
  instance_eval do
    autoload :ZZZ, './zzz.rb'
    begin
      ZZZ
    rescue NameError
      :ok
    end
  end
}, '[ruby-dev:43816]'

assert_equal 'ok', %q{
  open('zzz.rb', 'w') {|f| f.puts 'class ZZZ; def self.ok;:ok;end;end'}
  instance_eval do
    autoload :ZZZ, './zzz.rb'
    ZZZ.ok
  end
}, '[ruby-dev:43816]'

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

assert_equal 'okok', %q{
  open("zzz.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz.rb"
  t1 = Thread.new {ZZZ.ok}
  t2 = Thread.new {ZZZ.ok}
  [t1.value, t2.value].join
}

assert_finish 5, %q{
  autoload :ZZZ, File.expand_path(__FILE__)
  begin
    ZZZ
  rescue NameError
  end
}, '[ruby-core:21696]'

assert_equal 'A::C', %q{
  open("zzz.rb", "w") {}
  class A
    autoload :C, "./zzz"
    class C
    end
    C
  end
}
