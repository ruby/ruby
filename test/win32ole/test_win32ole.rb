#
# This script check that Win32OLE can execute InvokeVerb method of FolderItem2.
#

begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE)
  class TestWin32OLE < Test::Unit::TestCase
    def test_invoke_accept_symbol_hash_key
      fso = WIN32OLE.new('Scripting.FileSystemObject')
      afolder = fso.getFolder(".")
      bfolder = fso.getFolder({"FolderPath" => "."})
      cfolder = fso.getFolder({:FolderPath => "."})
      assert_equal(afolder.path, bfolder.path)
      assert_equal(afolder.path, cfolder.path)
      fso = nil
    end
    def test_invoke_hash_key_non_str_sym
      fso = WIN32OLE.new('Scripting.FileSystemObject')
      begin
        bfolder = fso.getFolder({1 => "."})
        assert(false)
      rescue TypeError
        assert(true)
      end
      fso = nil
    end
    def test_invoke_accept_multi_hash_key
      shell = WIN32OLE.new('Shell.Application')
      folder = shell.nameSpace(0)
      item = folder.items.item(0)
      name = folder.getDetailsOf(item, 0)
      assert_equal(item.name, name)
      name = folder.getDetailsOf({:vItem => item, :iColumn => 0})
      assert_equal(item.name, name)
      name = folder.getDetailsOf({"vItem" => item, :iColumn => 0})
      assert_equal(item.name, name)
    end

    def test_bracket
      dict = WIN32OLE.new('Scripting.Dictionary')
      dict.add("foo", "FOO")
      assert_equal("FOO", dict.item("foo"))
      assert_equal("FOO", dict["foo"])
    end

    def test_bracket_equal
      dict = WIN32OLE.new('Scripting.Dictionary')
      dict.add("foo", "FOO")
      dict["foo"] = "BAR"
      assert_equal("BAR", dict["foo"])
    end
  end
end
