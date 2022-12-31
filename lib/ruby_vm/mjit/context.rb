class RubyVM::MJIT::Context < Struct.new(
  :stack_size, # @param [Integer] The number of values on the stack
  :sp_offset,  # @param [Integer] JIT sp offset relative to the interpreter's sp
)
  def initialize(*)
    super
    self.stack_size ||= 0
    self.sp_offset ||= 0
  end

  def stack_push(size)
    self.stack_size += size
    self.sp_offset += size
  end
end
