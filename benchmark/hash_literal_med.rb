pairs = (0...256).map { |i| ":k#{i} => #{i}" }.join(', ')
eval <<~RUBY
  def make_hash_med
    { #{pairs} }
  end
RUBY

50_000.times { make_hash_med }
