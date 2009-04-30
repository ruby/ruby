require 'test/unit'
require 'rbconfig'
require 'optparse'

if /mswin32/ !~ RUBY_PLATFORM
  $ruby = './miniruby'
else
  $ruby = 'miniruby'
end
$matzruby = RbConfig::CONFIG['ruby_install_name']

ARGV.each{|opt|
  if /\Aruby=(.+)/ =~ opt
    $ruby = $1
  elsif /\Amatzruby=(.+)/ =~ opt
    $matzruby = $1
  end
}

a = "matzruby: #{`#{$matzruby} -v`}"
b = "ruby    : #{`#{$ruby} -v`}"
puts a, b
raise "Using same command" if a == b

class YarvTestBase < Test::Unit::TestCase
  def initialize *args
    super

  end

  def remove_const sym
    Object.module_eval{
      remove_const sym
    }
  end

  def remove_method sym
    Object.module_eval{
      undef sym
    }
  end

  require 'tempfile'
  def exec exec_file, program
    dir = []
    dir << ENV['RAMDISK'] if ENV['RAMDISK']
    tmpf = Tempfile.new("yarvtest_#{Process.pid}_#{Time.now.to_i}", *dir)
    tmpf.write program
    tmpf.close
    result = `#{exec_file} #{tmpf.path}`
    tmpf.open
    tmpf.close(true)
    result
  end

  def dump_and_exec exec_file, str
    asmstr = <<-EOASMSTR
      iseq = YARVCore::InstructionSequence.compile(<<-'EOS__')
      #{str}
      EOS__
      p YARVCore::InstructionSequence.load(iseq.to_a).eval
    EOASMSTR

    exec(exec_file, asmstr)
  end

  def exec_ exec_file, program
    exec_file.tr!('\\', '/')
    r = ''
    IO.popen("#{exec_file}", 'r+'){|io|
      #
      io.write program
      io.close_write
      begin
        while line = io.gets
          r << line
          # p line
        end
      rescue => e
        # p e
      end
    }
    r
  end
  
  def ae str
    evalstr = %{
      p eval(%q{
        #{str}
      })
    }

    matzruby = exec($matzruby, evalstr)
    ruby = exec($ruby, evalstr)

    if $DEBUG #|| true
      puts "matzruby (#$matzruby): #{matzruby}"
      puts "ruby     (#$ruby): #{ruby}"
    end

    assert_equal(matzruby.gsub(/\r/, ''), ruby.gsub(/\r/, ''), str)

    # store/load test
    if false # || true
      yarvasm = dump_and_exec($ruby, str)
      assert_equal(ruby.gsub(/\r/, ''), yarvasm.gsub(/\r/, ''))
    end
  end
  
  def test_
  end
end
