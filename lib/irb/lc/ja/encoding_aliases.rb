# frozen_string_literal: false
module IRB
  # :stopdoc:

  class Locale
    @@legacy_encoding_alias_map = {
      'ujis' => Encoding::EUC_JP,
      'euc' => Encoding::EUC_JP
    }.freeze
  end

  # :startdoc:
end
