# frozen_string_literal: true
require 'test/unit'

class TestVMDump < Test::Unit::TestCase
  def assert_darwin_vm_dump_works(args)
    omit if RUBY_PLATFORM !~ /darwin/
    assert_in_out_err(args, "", [], /^\[IMPORTANT\]/)
  end

  def test_darwin_invalid_call
    assert_darwin_vm_dump_works(['-rfiddle', '-eFiddle::Function.new(Fiddle::Pointer.new(1), [], Fiddle::TYPE_VOID).call'])
  end

  def test_darwin_segv_in_syscall
    assert_darwin_vm_dump_works('-e1.times{Process.kill :SEGV,$$}')
  end

  def test_darwin_invalid_access
    assert_darwin_vm_dump_works(['-rfiddle', '-eFiddle.dlunwrap(100).inspect'])
  end
end
