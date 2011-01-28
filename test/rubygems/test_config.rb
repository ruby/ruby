######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems'

class TestConfig < Gem::TestCase

  def test_datadir
    _, err = capture_io do
      datadir = RbConfig::CONFIG['datadir']
      assert_equal "#{datadir}/xyz", RbConfig.datadir('xyz')
    end

    assert_match(/deprecate/, err)
  end

end

