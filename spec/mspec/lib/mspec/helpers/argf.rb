# Convenience helper for specs using ARGF.
# Set @argf to an instance of ARGF.class with the given +argv+.
# That instance must be used instead of ARGF as ARGF is global
# and it is not always possible to reset its state correctly.
#
# The helper yields to the block and then close
# the files open by the instance. Example:
#
#   describe "That" do
#     it "does something" do
#       argf ['a', 'b'] do
#         # do something
#       end
#     end
#   end
def argf(argv)
  if argv.empty? or argv.length > 2
    raise "Only 1 or 2 filenames are allowed for the argf helper so files can be properly closed: #{argv.inspect}"
  end
  @argf ||= nil
  raise "Cannot nest calls to the argf helper" if @argf

  @argf = ARGF.class.new(*argv)
  @__mspec_saved_argf_file__ = @argf.file
  begin
    yield
  ensure
    file1 = @__mspec_saved_argf_file__
    file2 = @argf.file # Either the first file or the second
    file1.close if !file1.closed? and file1 != STDIN
    file2.close if !file2.closed? and file2 != STDIN
    @argf = nil
    @__mspec_saved_argf_file__ = nil
  end
end
