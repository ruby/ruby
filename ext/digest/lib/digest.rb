module Digest
  autoload "MD5", "digest/md5"
  autoload "RMD160", "digest/rmd160"
  autoload "SHA1", "digest/sha1"
  autoload "SHA256", "digest/sha2"
  autoload "SHA384", "digest/sha2"
  autoload "SHA512", "digest/sha2"

  class Base
    # creates a digest object and read given file, _name_.
    # 
    #  p Digest::SHA256.file("X11R6.8.2-src.tar.bz2").hexdigest
    #  # => "f02e3c85572dc9ad7cb77c2a638e3be24cc1b5bea9fdbb0b0299c9668475c534"
    def self.file(name)
      digest = self.new
      File.open(name, "rb") {|f|
        buf = ""
        while f.read(16384, buf)
          digest.update buf
        end
      }
      digest
    end
  end
end
