class RubyVM::MJIT::Context < Struct.new(
  :stack_size, # @param [Integer]
)
  def initialize(*)
    super
    self.stack_size ||= 0
  end
end
