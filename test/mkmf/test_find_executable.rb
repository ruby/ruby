require File.join(File.dirname(__FILE__), 'base')

class TestMkmf
  class TestFindExecutable < TestMkmf
    class F
      def do_find_executable(name)
        find_executable(name)
      end
    end

    def test_find_executable
      bug2669 = '[ruby-core:27912]'
      path, ENV["PATH"] = ENV["PATH"], path
      ENV["PATH"] = @tmpdir
      f = F.new
      name = "foobar#{$$}#{rand(1000)}"
      if /mswin\d|mingw|cygwin/ =~ RUBY_PLATFORM
        exts = %w[.exe .com .cmd .bat]
      else
        exts = [""]
      end
      exts.each do |ext|
        full = name+ext
        begin
          open(full, "w") {|ff| ff.chmod(0755)}
          result = f.do_find_executable(name)
        ensure
          File.unlink(full)
        end
        assert_equal("#{@tmpdir}/#{name}#{ext}", result, bug2669)
      end
    ensure
      ENV["PATH"] = path
    end
  end
end
