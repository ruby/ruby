require_relative 'base'

class TestMkmf
  class TestHaveFramework < TestMkmf
    def create_framework(fw, hdrname = "#{fw}.h")
      Dir.mktmpdir("frameworks") do |dir|
        fwdir = "#{dir}/#{fw}.framework"
        hdrdir = "#{fwdir}/Headers"
        FileUtils.mkdir_p(hdrdir)
        File.write("#{hdrdir}/#{hdrname}", "")
        src = "#{fwdir}/main.c"
        File.write(src, "void #{fw}(void) {}")
        cmd = LINK_SO.dup
        RbConfig.expand(cmd, RbConfig::CONFIG.merge("OBJS"=>src))
        cmd.gsub!("$@", "#{fwdir}/#{fw}")
        cmd.gsub!(/ -bundle /, ' -dynamiclib ')
        assert(xsystem(cmd), MKMFLOG)
        $INCFLAGS << " " << "-F#{dir}".quote
        yield fw, hdrname
      end
    end

    def test_core_foundation_framework
      assert(have_framework("CoreFoundation"), mkmflog("try as Objective-C"))
    end

    def test_multi_frameworks
      assert(have_framework("CoreFoundation"), mkmflog("try as Objective-C"))
      create_framework("MkmfTest") do |fw|
        assert(have_framework(fw), MKMFLOG)
      end
    end

    def test_empty_framework
      create_framework("MkmfTest") do |fw|
        assert(have_framework(fw), MKMFLOG)
      end
    end

    def test_different_name_header
      _bug8593 = '[ruby-core:55745] [Bug #8593]'
      create_framework("MkmfTest", "test_mkmf.h") do |fw, hdrname|
        assert(!have_framework(fw), MKMFLOG)
        assert(have_framework([fw, hdrname]), MKMFLOG)
      end
    end
  end
end if /darwin/ =~ RUBY_PLATFORM
