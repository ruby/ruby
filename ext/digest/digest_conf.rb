# frozen_string_literal: false

def digest_conf(name)
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
  end
  $objs << "#{name}.#{$OBJEXT}"
  return
end
