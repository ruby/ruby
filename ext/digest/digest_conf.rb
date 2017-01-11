# frozen_string_literal: false
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
    require File.expand_path('../../openssl/deprecation', __FILE__)
    if have_library("crypto")
      funcs ||= name.upcase
      funcs = Array(funcs)
      types ||= funcs
      hdr = "openssl/#{hdr}.h"
      if funcs.all? {|func| OpenSSL.check_func("#{func}_Transform", hdr)} &&
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
