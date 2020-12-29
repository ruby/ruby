#
# call-seq:
#    Time.now -> time
#
# Creates a new Time object for the current time.
# This is same as Time.new without arguments.
#
#    Time.now            #=> 2009-06-24 12:39:54 +0900
def Time.now(in: nil)
  __builtin.time_s_now(__builtin.arg!(:in))
end
