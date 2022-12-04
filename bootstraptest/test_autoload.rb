assert_equal 'ok', %q{
  File.unlink('zzz1.rb') if File.file?('zzz1.rb')
  instance_eval do
    autoload :ZZZ, './zzz1.rb'
    begin
      ZZZ
    rescue LoadError
      :ok
    end
  end
}, '[ruby-dev:43816]'

assert_equal 'ok', %q{
  open('zzz2.rb', 'w') {|f| f.puts '' }
  instance_eval do
    autoload :ZZZ, './zzz2.rb'
    begin
      ZZZ
    rescue NameError
      :ok
    end
  end
}, '[ruby-dev:43816]'

assert_equal 'ok', %q{
  open('zzz3.rb', 'w') {|f| f.puts 'class ZZZ; def self.ok;:ok;end;end'}
  instance_eval do
    autoload :ZZZ, './zzz3.rb'
    ZZZ.ok
  end
}, '[ruby-dev:43816]'

assert_equal 'ok', %q{
  open("zzz4.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz4.rb"
  ZZZ.ok
}

assert_equal 'ok', %q{
  open("zzz5.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz5.rb"
  require "./zzz5.rb"
  ZZZ.ok
}

assert_equal 'okok', %q{
  open("zzz6.rb", "w") {|f| f.puts "class ZZZ; def self.ok;:ok;end;end"}
  autoload :ZZZ, "./zzz6.rb"
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
  open("zzz7.rb", "w") {}
  class A
    autoload :C, "./zzz7"
    class C
    end
    C
  end
}
