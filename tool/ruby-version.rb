#!/usr/bin/env ruby

module RubyVersion
  def self.tag(version)
    major_version = Integer(version.split('.', 2)[0])
    if major_version >= 4
      "v#{version}"
    else
      "v#{version.tr('.-', '_')}"
    end
  end

  # Return the previous version to be used for release diff links.
  # For a ".0" version, it returns the previous ".0" version.
  # For a non-".0" version, it returns the previous teeny version.
  def self.previous(version)
    unless /\A(\d+)\.(\d+)\.(\d+)(?:-(?:preview|rc)\d+)?\z/ =~ version
      raise "unexpected version string '#{version}'"
    end
    major = Integer($1)
    minor = Integer($2)
    teeny = Integer($3)

    if teeny != 0
      "#{major}.#{minor}.#{teeny-1}"
    elsif minor != 0 # && teeny == 0
      "#{major}.#{minor-1}.#{teeny}"
    else # minor == 0 && teeny == 0
      case major
      when 3
        "2.7.0"
      when 4
        "3.4.0"
      else
        raise "it doesn't know what is the previous version of '#{version}'"
      end
    end
  end
end

if __FILE__ == $0
  case ARGV[0]
  when "tag"
    print RubyVersion.tag(ARGV[1])
  when "previous"
    print RubyVersion.previous(ARGV[1])
  when "previous-tag"
    print RubyVersion.tag(RubyVersion.previous(ARGV[1]))
  else
    "#{$0}: unexpected command #{ARGV[0].inspect}"
  end
end
