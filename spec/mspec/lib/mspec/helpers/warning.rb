require 'mspec/guards/version'

def suppress_warning
  verbose = $VERBOSE
  $VERBOSE = nil
  yield
ensure
  $VERBOSE = verbose
end

if ruby_version_is("2.7")
  def suppress_keyword_warning(&block)
    suppress_warning(&block)
  end
else
  def suppress_keyword_warning
    yield
  end
end
