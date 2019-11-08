class << Thread
  # call-seq:
  #    Thread.exclusive { block }   -> obj
  #
  # Wraps the block in a single, VM-global Mutex.synchronize, returning the
  # value of the block. A thread executing inside the exclusive section will
  # only block other threads which also use the Thread.exclusive mechanism.
  def exclusive(&block) end if false
  mutex = Mutex.new # :nodoc:
  define_method(:exclusive) do |&block|
    warn "Thread.exclusive is deprecated, use Thread::Mutex", uplevel: 1
    mutex.synchronize(&block)
  end
end

class Binding
  # :nodoc:
  def irb
    require 'irb'
    irb
  end

  # suppress redefinition warning
  alias irb irb # :nodoc:
end

module Kernel
  def pp(*objs)
    require 'pp'
    pp(*objs)
  end

  # suppress redefinition warning
  alias pp pp # :nodoc:

  private :pp
end
