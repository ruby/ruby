# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestStack < Test::Unit::TestCase
  LARGE_VM_STACK_SIZE = 1024*1024*5
  LARGE_MACHINE_STACK_SIZE = 1024*1024*10

  def initialize(*)
    super

    @h_default = nil
    @h_0 = nil
    @h_large = nil
  end

  def invoke_ruby script, vm_stack_size: nil, machine_stack_size: nil
    env = {}
    env['RUBY_FIBER_VM_STACK_SIZE'] = vm_stack_size.to_s if vm_stack_size
    env['RUBY_FIBER_MACHINE_STACK_SIZE'] = machine_stack_size.to_s if machine_stack_size

    stdout, stderr, status = EnvUtil.invoke_ruby([env, '-e', script], '', true, true, timeout: 30)
    assert(!status.signaled?, FailDesc[status, nil, stderr])

    return stdout
  end

  def h_default
    @h_default ||= eval(invoke_ruby('p RubyVM::DEFAULT_PARAMS'))
  end

  def h_0
    @h_0 ||= eval(invoke_ruby('p RubyVM::DEFAULT_PARAMS',
      vm_stack_size: 0,
      machine_stack_size: 0
    ))
  end

  def h_large
    @h_large ||= eval(invoke_ruby('p RubyVM::DEFAULT_PARAMS',
      vm_stack_size: LARGE_VM_STACK_SIZE,
      machine_stack_size: LARGE_MACHINE_STACK_SIZE
    ))
  end

  def test_relative_stack_sizes
    assert_operator(h_default[:fiber_vm_stack_size], :>, h_0[:fiber_vm_stack_size])
    assert_operator(h_default[:fiber_vm_stack_size], :<, h_large[:fiber_vm_stack_size])
    assert_operator(h_default[:fiber_machine_stack_size], :>=, h_0[:fiber_machine_stack_size])
    assert_operator(h_default[:fiber_machine_stack_size], :<=, h_large[:fiber_machine_stack_size])
  end

  def test_vm_stack_size
    script = '$stdout.sync=true; def rec; print "."; rec; end; Fiber.new{rec}.resume'

    size_default = invoke_ruby(script).bytesize
    assert_operator(size_default, :>, 0)

    size_0 = invoke_ruby(script, vm_stack_size: 0).bytesize
    assert_operator(size_default, :>, size_0)

    size_large = invoke_ruby(script, vm_stack_size: LARGE_VM_STACK_SIZE).bytesize
    assert_operator(size_default, :<, size_large)
  end

  # Depending on OS, machine stack size may not change size.
  def test_machine_stack_size
    return if /mswin|mingw/ =~ RUBY_PLATFORM

    script = '$stdout.sync=true; def rec; print "."; 1.times{1.times{1.times{rec}}}; end; Fiber.new{rec}.resume'

    vm_stack_size = 1024 * 1024
    size_default = invoke_ruby(script, vm_stack_size: vm_stack_size).bytesize

    size_0 = invoke_ruby(script, vm_stack_size: vm_stack_size, machine_stack_size: 0).bytesize
    assert_operator(size_default, :>=, size_0)

    size_large = invoke_ruby(script, vm_stack_size: vm_stack_size, machine_stack_size: LARGE_MACHINE_STACK_SIZE).bytesize
    assert_operator(size_default, :<=, size_large)
  end
end
