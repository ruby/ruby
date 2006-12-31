require 'test/unit'

if defined? YARV_PATCHED
require 'yarvutil'

class YarvTestBase < Test::Unit::TestCase

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
  
  def ae str
    # puts str
    # puts YARVUtil.parse(str, $0, 0).disasm

    ruby = YARVUtil.eval_in_wrap(str)
    yield if block_given?

    yarv = YARVUtil.eval(str)
    yield if block_given?

    assert_equal(ruby, yarv)
  end
  
  def test_
  end

end

else

require 'rbconfig'
class YarvTestBase < Test::Unit::TestCase
  def initialize *args
    super

    if /mswin32/ !~ RUBY_PLATFORM
      @yarv = './miniruby'
    else
      @yarv = 'miniruby'
    end
    @ruby = Config::CONFIG['ruby_install_name']
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

    ruby = exec(@ruby, evalstr)
    yarv = exec(@yarv, evalstr)

    if $DEBUG #|| true
      puts "yarv (#@yarv): #{yarv}"
      puts "ruby (#@ruby): #{ruby}"
    end

    assert_equal(ruby.gsub(/\r/, ''), yarv.gsub(/\r/, ''))

    # store/load test
    if false # || true
      yarvasm = dump_and_exec(@yarv, str)
      assert_equal(ruby.gsub(/\r/, ''), yarvasm.gsub(/\r/, ''))
    end
  end
  
  def test_
  end
end

end
