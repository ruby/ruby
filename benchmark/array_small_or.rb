MIN_SIZE = ENV.fetch('SMALL_ARRAY_MIN', 0).to_i
MAX_SIZE = ENV.fetch('SMALL_ARRAY_MAX', 16).to_i
ITERATIONS = ENV.fetch('SMALL_ARRAY_ITERATIONS', 100).to_i

ARRAYS = (MIN_SIZE..MAX_SIZE).map do |size1|
  (MIN_SIZE..MAX_SIZE).map do |size2|
    [Array.new(size1) { rand(MAX_SIZE) }, Array.new(size2) { rand(MAX_SIZE) }]
  end
end

ITERATIONS.times do
  ARRAYS.each do |group|
    group.each do |arr1, arr2|
      arr1 | arr2
    end
  end
end
