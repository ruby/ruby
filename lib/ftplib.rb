#
# ftplib.rb
#

$stderr.puts 'Warning: ftplib.rb is obsolute: use net/ftp'

require 'net/ftp'

FTP           = ::Net::FTP
FTPError      = ::Net::FTPError
FTPReplyError = ::Net::FTPReplyError
FTPTempError  = ::Net::FTPTempError
FTPPermError  = ::Net::FTPPermError
FTPProtoError = ::Net::FTPProtoError
