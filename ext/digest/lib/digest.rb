module Digest
  autoload "MD5", "digest/md5"
  autoload "RMD160", "digest/rmd160"
  autoload "SHA1", "digest/sha1"
  autoload "SHA256", "digest/sha2"
  autoload "SHA384", "digest/sha2"
  autoload "SHA512", "digest/sha2"

  class Base
    def self.file(name)
      digest = self.new
      File.open(name) {|f|
        buf = ""
        while f.read(16384, buf)
          digest.update buf
        end
      }
      digest
    end
  end
end
