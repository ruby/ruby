begin
  verbose, $VERBOSE = $VERBOSE, nil
  require "base64"
rescue LoadError
ensure
  $VERBOSE = verbose
end

require "base64"
