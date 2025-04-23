ractors = 5.times.map do |i|
  Ractor.new do
    100_000.times.map do
      o = Object.new
      ObjectSpace.define_finalizer(o, ->(id) {})
      o
    end
  end
end

ractors.each(&:take)

