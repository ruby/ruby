# frozen_string_literal: true
require 'test/unit'

return unless /darwin/ =~ RUBY_PLATFORM

class TestVMDump < Test::Unit::TestCase
  def assert_darwin_vm_dump_works(args, timeout=nil)
    pend "macOS 15 beta is not working with this assertion" if /darwin/ =~ RUBY_PLATFORM && /15/ =~ `sw_vers -productVersion`

    assert_in_out_err(args, "", [], /^\[IMPORTANT\]/, timeout: timeout || 60)
  end

  def test_darwin_invalid_call
    assert_darwin_vm_dump_works(['-r-test-/fatal', '-eBug.invalid_call(1)'], 180)
  end

  def test_darwin_segv_in_syscall
    assert_darwin_vm_dump_works('-e1.times{Process.kill :SEGV,$$}')
  end

  def test_darwin_invalid_access
    assert_darwin_vm_dump_works(['-r-test-/fatal', '-eBug.invalid_access(100)'])
  end
end
