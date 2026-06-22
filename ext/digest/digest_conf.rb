# frozen_string_literal: false

def digest_conf(name)
  unless with_config("bundled-#{name}")
    case cc = with_config("common-digest", true)
    when true, false
    else
      cc = cc.split(/[\s,]++/).any? {|pat| File.fnmatch?(pat, name)}
    end
    if cc and File.exist?("#$srcdir/#{name}cc.h") and
      have_header("CommonCrypto/CommonDigest.h")
      $defs << "-D#{name.upcase}_USE_COMMONDIGEST"
      $headers << "#{name}cc.h"
      return :commondigest
    end
  end
  $objs << "#{name}.#{$OBJEXT}"
  return
end
