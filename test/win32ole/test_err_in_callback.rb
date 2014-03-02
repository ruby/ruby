#
# test Win32OLE avoids cfp consistency error when the exception raised
# in WIN32OLE_EVENT handler block. [ruby-dev:35450]
#

begin
  require 'win32ole'
rescue LoadError
end
if defined?(WIN32OLE)
  require 'mkmf'
  require 'pathname'
  require 'test/unit'
  require 'tmpdir'
  class TestErrInCallBack < Test::Unit::TestCase
    def setup
      @ruby = nil
      if File.exist?("./" + CONFIG["RUBY_INSTALL_NAME"] + CONFIG["EXEEXT"])
        sep = File::ALT_SEPARATOR || "/"
        @ruby = "." + sep + CONFIG["RUBY_INSTALL_NAME"]
        cwd = Pathname.new(File.expand_path('.'))
        @iopt = $:.map {|e|
          " -I " + (Pathname.new(e).relative_path_from(cwd).to_s rescue e)
        }.join("")
        script = File.join(File.dirname(__FILE__), "err_in_callback.rb")
        @script = Pathname.new(script).relative_path_from(cwd).to_s rescue script
      end
    end

    def available_adodb?
      begin
        WIN32OLE.new('ADODB.Connection')
      rescue WIN32OLERuntimeError
        return false
      end
      return true
    end

    def test_err_in_callback
      skip "'ADODB.Connection' is not available" unless available_adodb?
      if @ruby
        Dir.mktmpdir do |tmpdir|
          logfile = File.join(tmpdir, "test_err_in_callback.log")
          cmd = "#{@ruby} -v #{@iopt} #{@script} > #{logfile.gsub(%r(/), '\\')} 2>&1"
          system(cmd)
          str = ""
          open(logfile) {|ifs|
            str = ifs.read
          }
          assert_match(/NameError/, str)
        end
      end
    end
  end
end
