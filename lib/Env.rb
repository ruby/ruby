# Env.rb -- imports environment variables as global variables, Perlish ;(
# Usage:
#
#  require 'Env'
#  p $USER
#  $USER = "matz"
#  p ENV["USER"]

require 'importenv'

if __FILE__ == $0
  p $TERM
  $TERM = nil
  p $TERM
  p ENV["TERM"]
  $TERM = "foo"
  p ENV["TERM"]
end
