module ENVSpecs
  def self.encoding
    locale = Encoding.find('locale')
    if ruby_version_is '3' and platform_is :windows
      locale = Encoding::UTF_8
    end
    locale
  end
end
