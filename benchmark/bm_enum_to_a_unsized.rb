class SizelessEnum
  include Enumerable

  def initialize(n)
    @n = n
  end

  def each
    @n.times { |i| yield i }
  end

end

(2**15).times do |i|
  ary = SizelessEnum.new(i).to_a
end
