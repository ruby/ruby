require 'openssl'

class OpenSSLVersionGuard < VersionGuard
  FULL_OPENSSL_VERSION = SpecVersion.new OpenSSL::VERSION
  def match?
    if Range === @version
      @version.include? FULL_OPENSSL_VERSION
    else
      FULL_OPENSSL_VERSION >= @version
    end
  end
end

def openssl_version_is(*args, &block)
  OpenSSLVersionGuard.new(*args).run_if(:openssl_version_is, &block)
end
