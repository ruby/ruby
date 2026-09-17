module ENVSpecs
  def self.encoding
    return Encoding::UTF_8 if platform_is :windows

    Encoding.find('locale')
  end
end
