class RubyVM::MJIT::Context < Struct.new(
  :stack_size, # @param [Integer] The number of values on the stack
  :sp_offset,  # @param [Integer] JIT sp offset relative to the interpreter's sp
)
  def initialize(stack_size: 0, sp_offset: 0) = super

  def stack_push(size)
    self.stack_size += size
    self.sp_offset += size
  end

  def stack_pop(size)
    stack_push(-size)
  end
end
