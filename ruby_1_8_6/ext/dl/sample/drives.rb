# -*- ruby -*-
# drives.rb -- find existing drives and show the drive type.

require 'dl'
require 'dl/import'

module Kernel32
  extend DL::Importable

  dlload "kernel32"

  extern "long GetLogicalDrives()"
  extern "int GetDriveType(char*)"
  extern "long GetDiskFreeSpace(char*, long ref, long ref, long ref, long ref)"
end

include Kernel32

buff = Kernel32.getLogicalDrives()

i = 0
ds = []
while( i < 26 )
  mask = (1 << i)
  if( buff & mask > 0 )
    ds.push((65+i).chr)
  end
  i += 1
end

=begin
From the cygwin's /usr/include/w32api/winbase.h:
#define DRIVE_UNKNOWN 0
#define DRIVE_NO_ROOT_DIR 1
#define DRIVE_REMOVABLE 2
#define DRIVE_FIXED 3
#define DRIVE_REMOTE 4
#define DRIVE_CDROM 5
#define DRIVE_RAMDISK 6
=end

types = [
  "unknown",
  "no root dir",
  "Removable",
  "Fixed", 
  "Remote",
  "CDROM",
  "RAM",
]
print("Drive : Type (Free Space/Available Space)\n")
ds.each{|d|
  t = Kernel32.getDriveType(d + ":\\")
  Kernel32.getDiskFreeSpace(d + ":\\", 0, 0, 0, 0)
  _,sec_per_clus,byte_per_sec,free_clus,total_clus = Kernel32._args_
  fbytes = sec_per_clus * byte_per_sec * free_clus
  tbytes = sec_per_clus * byte_per_sec * total_clus
  unit = "B"
  if( fbytes > 1024 && tbytes > 1024 )
    fbytes = fbytes / 1024
    tbytes = tbytes / 1024
    unit = "K"
  end
  if( fbytes > 1024 && tbytes > 1024 )
    fbytes = fbytes / 1024
    tbytes = tbytes / 1024
    unit = "M"
  end
  print("#{d} : #{types[t]} (#{fbytes} #{unit}/#{tbytes} #{unit})\n")
}
