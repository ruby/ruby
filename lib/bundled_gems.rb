module Gem
  # https://bugs.ruby-lang.org/issues/19351
  def self.bundled_gems
    %w[
      abbrev
      getoptlong
      observer
      resolv-replace
      rinda
      nkf
      syslog
      drb
      mutex_m
      csv
      base64
    ]
  end
end
