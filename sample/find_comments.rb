# This script finds all of the comments within a given source file.

require "prism"

Prism.parse_comments(DATA.read).each do |comment|
  puts comment.inspect
  puts comment.slice
end

# =>
# #<Prism::InlineComment @location=#<Prism::Location @start_offset=0 @length=42 start_line=1>>
# # This is documentation for the Foo class.
# #<Prism::InlineComment @location=#<Prism::Location @start_offset=55 @length=43 start_line=3>>
# # This is documentation for the bar method.

__END__
# This is documentation for the Foo class.
class Foo
  # This is documentation for the bar method.
  def bar
  end
end
