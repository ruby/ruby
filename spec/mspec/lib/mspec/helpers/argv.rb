# Convenience helper for altering ARGV. Saves the
# value of ARGV and sets it to +args+. If a block
# is given, yields to the block and then restores
# the value of ARGV. The previously saved value of
# ARGV can be restored by passing +:restore+. The
# former is useful in a single spec. The latter is
# useful in before/after actions. For example:
#
#   describe "This" do
#     before do
#       argv ['a', 'b']
#     end
#
#     after do
#       argv :restore
#     end
#
#     it "does something" do
#       # do something
#     end
#   end
#
#   describe "That" do
#     it "does something" do
#       argv ['a', 'b'] do
#         # do something
#       end
#     end
#   end
def argv(args)
  if args == :restore
    ARGV.replace(@__mspec_saved_argv__ || [])
  else
    @__mspec_saved_argv__ = ARGV.dup
    ARGV.replace args
    if block_given?
      begin
        yield
      ensure
        argv :restore
      end
    end
  end
end
