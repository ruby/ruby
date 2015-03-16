def digest_conf(name, hdr = name, funcs = nil)
  unless with_config("bundled-#{name}")
    cc = with_config("common-digest")
    if cc == true or /\b#{name}\b/ =~ cc
      if File.exist?("#$srcdir/#{name}cc.h") and
        have_header("CommonCrypto/CommonDigest.h")
        $defs << "-D#{name.upcase}_USE_COMMONDIGEST"
        return :commondigest
      end
    end

    dir_config("openssl")
    pkg_config("openssl")
    require File.expand_path('../../openssl/deprecation', __FILE__)
    if have_library("crypto")
      funcs ||= name.upcase
      funcs = Array(funcs)
      hdr = "openssl/#{hdr}.h"
      if funcs.all? {|func| OpenSSL.check_func("#{func}_Transform", hdr)} &&
         funcs.all? {|func| have_type("#{func}_CTX", hdr)}
        $defs << "-D#{name.upcase}_USE_OPENSSL"
        return :ossl
      end
    end
  end
  $objs << "#{name}.#{$OBJEXT}"
  return
end
