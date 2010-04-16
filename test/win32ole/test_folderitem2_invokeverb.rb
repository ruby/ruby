#
# This script check that Win32OLE can execute InvokeVerb method of FolderItem2.
#

begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE)
  class TestInvokeVerb < Test::Unit::TestCase
    def setup
      #
      # make dummy.txt file for InvokeVerb test.
      #

      @fso = WIN32OLE.new('Scripting.FileSystemObject')
      @dummy_file = @fso.GetTempName
      @cfolder = @fso.getFolder(".")
      f = @cfolder.CreateTextFile(@dummy_file)
      f.close
      @dummy_path = @cfolder.path + "\\" + @dummy_file

      @shell=WIN32OLE.new('Shell.Application')
      @nsp = @shell.NameSpace(@cfolder.path)
      @fi2 = @nsp.parseName(@dummy_file)

      @shortcut = nil

      #
      # Search the 'Create Shortcut (&S)' string in Japanese.
      # Yes, I know the string in the Windows 2000 Japanese Edition.
      # But I do not know about the string in any other Windows.
      #
      verbs = @fi2.verbs
      verbs.extend(Enumerable)
      @cp = WIN32OLE.codepage
      begin
        WIN32OLE.codepage = 932
      rescue
      end
      @shortcut = verbs.collect{|verb|
        verb.name
      }.find {|name|
        name.unpack("C*") == [131, 86, 131, 135, 129, 91, 131, 103, 131, 74, 131, 98, 131, 103, 130, 204, 141, 236, 144, 172, 40, 38, 83, 41]
        # /.*\(\&S\)$/ =~ name
      }
    end

    def find_link(path)
      arlink = []
      @cfolder.files.each do |f|
        if /\.lnk$/ =~ f.path
          linkinfo = @nsp.parseName(f.name).getLink
          arlink.push f if linkinfo.path == path
        end
      end
      arlink
    end

    def test_invokeverb
      # this test should run only when "Create Shortcut (&S)" 
      # is found in context menu,
      if @shortcut
        links = find_link(@dummy_path)
        assert(0, links.size)

        # Now create shortcut to @dummy_path
        arg = WIN32OLE_VARIANT.new(@shortcut)
        @fi2.InvokeVerb(arg)

        # Now search shortcut to @dummy_path
        links = find_link(@dummy_path)
        assert(1, links.size)
        @lpath = links[0].path
      end
    end

    def teardown
      if @lpath
        @fso.deleteFile(@lpath)
      end
      if @dummy_path
        @fso.deleteFile(@dummy_path)
      end
      WIN32OLE.codepage = @cp
    end

  end
end
