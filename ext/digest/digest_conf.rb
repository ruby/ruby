# frozen_string_literal: false

# Copy from ext/openssl/extconf.rb
def find_openssl_library
  if $mswin || $mingw
    # required for static OpenSSL libraries
    have_library("gdi32") # OpenSSL <= 1.0.2 (for RAND_screen())
    have_library("crypt32")
  end

  return false unless have_header("openssl/ssl.h")

  ret = have_library("crypto", "CRYPTO_malloc") &&
    have_library("ssl", "SSL_new")
  return ret if ret

  if $mswin
    # OpenSSL >= 1.1.0: libcrypto.lib and libssl.lib.
    if have_library("libcrypto", "CRYPTO_malloc") &&
        have_library("libssl", "SSL_new")
      return true
    end

    # OpenSSL <= 1.0.2: libeay32.lib and ssleay32.lib.
    if have_library("libeay32", "CRYPTO_malloc") &&
        have_library("ssleay32", "SSL_new")
      return true
    end

    # LibreSSL: libcrypto-##.lib and libssl-##.lib, where ## is the ABI version
    # number. We have to find the version number out by scanning libpath.
    libpath = $LIBPATH.dup
    libpath |= ENV["LIB"].split(File::PATH_SEPARATOR)
    libpath.map! { |d| d.tr(File::ALT_SEPARATOR, File::SEPARATOR) }

    ret = [
      ["crypto", "CRYPTO_malloc"],
      ["ssl", "SSL_new"]
    ].all? do |base, func|
      result = false
      libs = ["lib#{base}-[0-9][0-9]", "lib#{base}-[0-9][0-9][0-9]"]
      libs = Dir.glob(libs.map{|l| libpath.map{|d| File.join(d, l + ".*")}}.flatten).map{|path| File.basename(path, ".*")}.uniq
      libs.each do |lib|
        result = have_library(lib, func)
        break if result
      end
      result
    end
    return ret if ret
  end
  return false
end

def digest_conf(name, hdr = name, funcs = nil, types = nil)
  unless with_config("bundled-#{name}")
    cc = with_config("common-digest")
    if cc == true or /\b#{name}\b/ =~ cc
      if File.exist?("#$srcdir/#{name}cc.h") and
        have_header("CommonCrypto/CommonDigest.h")
        $defs << "-D#{name.upcase}_USE_COMMONDIGEST"
        $headers << "#{name}cc.h"
        return :commondigest
      end
    end

    dir_config("openssl")
    pkg_config("openssl")
    if find_openssl_library
      funcs ||= name.upcase
      funcs = Array(funcs)
      types ||= funcs
      hdr = "openssl/#{hdr}.h"
      if funcs.all? {|func| have_func("#{func}_Transform", hdr)} &&
         types.all? {|type| have_type("#{type}_CTX", hdr)}
        $defs << "-D#{name.upcase}_USE_OPENSSL"
        $headers << "#{name}ossl.h"
        return :ossl
      end
    end
  end
  $objs << "#{name}.#{$OBJEXT}"
  return
end
