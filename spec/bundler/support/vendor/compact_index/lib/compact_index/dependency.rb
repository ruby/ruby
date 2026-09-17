# frozen_string_literal: true

module VendoredCompactIndex
  Dependency = Struct.new(:gem, :version, :platform, :checksum) do
    def version_and_platform
      if platform.nil? || platform == "ruby"
        version
      else
        "#{version}-#{platform}"
      end
    end
  end
end
