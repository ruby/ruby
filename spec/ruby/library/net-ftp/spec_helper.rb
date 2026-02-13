ruby_version_is ""..."4.1" do
  require "net/ftp"

  if defined?(Net::FTP.default_passive)
    Net::FTP.default_passive = false
  end
end
