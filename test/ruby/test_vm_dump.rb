# frozen_string_literal: true
require 'test/unit'

class TestVMDump < Test::Unit::TestCase
  def assert_vm_dump_works(args)
    assert_in_out_err(args, "", [], [:*, /^.* main \+ \d+$/, :*, /^\[IMPORTANT\]/, :*])
  end

  def test_darwin_invalid_call
    assert_vm_dump_works(['-rfiddle', '-eFiddle::Function.new(Fiddle::Pointer.new(1), [], Fiddle::TYPE_VOID).call'])
  end

  def test_darwin_segv_in_syscall
    assert_vm_dump_works('-e1.times{Process.kill :SEGV,$$}')
  end

  def test_darwin_invalid_access
    assert_vm_dump_works(['-rfiddle', '-eFiddle.dlunwrap(100).class'])
  end
end
