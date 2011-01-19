######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/doc_manager'

class TestGemDocManager < RubyGemTestCase

  def setup
    super

    @spec = quick_gem 'a'
    @manager = Gem::DocManager.new(@spec)
  end

  def test_uninstall_doc_unwritable
    orig_mode = File.stat(@spec.installation_path).mode

    # File.chmod has no effect on MS Windows directories (it needs ACL).
    if win_platform?
      skip("test_uninstall_doc_unwritable skipped on MS Windows")
    else
      File.chmod(0, @spec.installation_path)
    end

    assert_raises Gem::FilePermissionError do
      @manager.uninstall_doc
    end
  ensure
    File.chmod orig_mode, @spec.installation_path
  end

end

