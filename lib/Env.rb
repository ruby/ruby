# Env.rb -- imports environment variables as global variables
#
# Usage:
#
#  p $USER
#  $USER = "matz"
#  p ENV["USER"]

for k,v in ENV
  next unless /^[a-zA-Z][_a-zA-Z0-9]*/ =~ k
  eval <<EOS
  $#{k} = %q!#{v}!
  trace_var "$#{k}", proc{|v|
    ENV[%q!#{k}!] = v; 
    $#{k} = %q!#{v}!
    if v == nil
      untrace_var "$#{k}"
    end
  }
EOS
end

if __FILE__ == $0
  p $TERM
  $TERM = nil
  p $TERM
  p ENV["TERM"]
  $TERM = "foo"
  p ENV["TERM"]
end
