module Kernel
  def y *objects
    puts Psych.dump_stream(*objects)
  end
  private :y
end

