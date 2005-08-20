#
# This script check that Win32OLE can execute InvokeVerb method of FolderItem2.
#

require 'test/unit'
require 'win32ole'

class TestInvokeVerb < Test::Unit::TestCase
  def setup
    #
    # make dummy.txt file for InvokeVerb test.
    #
    ofs = open('dummy.txt', 'w')
    ofs.write('this is test')
    ofs.close

    @fso = WIN32OLE.new('Scripting.FileSystemObject')
    @dummy_path = @fso.GetAbsolutePathName('dummy.txt')

    @shell=WIN32OLE.new('Shell.Application')
    @fi2 = @shell.NameSpace(@dummy_path).ParentFolder.ParseName(@shell.NameSpace(@dummy_path).Title)
    @shortcut = nil

    #
    # Search the 'Create Shortcut (&S)' string.
    # Yes, I know the string in the Windows 2000 Japanese Edition.
    # But I do not know about the string in any other Windows.
    # 
    @fi2.verbs.each do |v|
      #
      # We expect the 'Create Shortcut' string is end with '(&S)'.
      #
      if /.*\(\&S\)$/ =~ v.name
        @shortcut = v.name
        break
      end
    end
  end

  def test_invokeverb
    # We expect there is no shortcut in this folder.
    link = Dir["*.lnk"].find {|f| true}
    assert(!link)

    # Now create shortcut to "dummy.txt"
    assert(@shortcut)
    arg = WIN32OLE_VARIANT.new(@shortcut)
    @fi2.InvokeVerb(arg)

    # We expect there is shortcut in this folder
    link = Dir["*.lnk"].find {|f| true}
    assert(link)

    # The shortcut is to the "dummy.txt"
    @lpath = @fso.GetAbsolutePathName(link)
    linkinfo = @shell.NameSpace(@lpath).Self.GetLink
    assert_equal(@dummy_path, linkinfo.path)
  end

  def teardown
    if @lpath
      @fso.deleteFile(@lpath)
    end
    if @dummy_path
      @fso.deleteFile(@dummy_path)
    end
  end

end

