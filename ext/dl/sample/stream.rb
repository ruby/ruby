# -*- ruby -*-
# Display a file name and stream names of a file with those size.

require 'dl'
require 'dl/import'

module NTFS
  extend DL::Importable

  dlload "kernel32.dll"

  OPEN_EXISTING         = 3
  GENERIC_READ          = 0x80000000
  BACKUP_DATA           = 0x00000001
  BACKUP_ALTERNATE_DATA = 0x00000004
  FILE_SHARE_READ       = 0x00000001
  FILE_FLAG_BACKUP_SEMANTICS = 0x02000000

  typealias "LPSECURITY_ATTRIBUTES", "void*"

  extern "BOOL BackupRead(HANDLE, PBYTE, DWORD, PDWORD, BOOL, BOOL, PVOID)"
  extern "BOOL BackupSeek(HANDLE, DWORD, DWORD, PDWORD, PDWORD, PVOID)"
  extern "BOOL CloseHandle(HANDLE)"
  extern "HANDLE CreateFile(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES,
                            DWORD, DWORD, HANDLE)"

  module_function

  def streams(filename)
    status = []
    h = createFile(filename,GENERIC_READ,FILE_SHARE_READ,nil,
		   OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,0)
    if( h != 0 )
      begin
	# allocate the memory for backup data used in backupRead().
	data = DL.malloc(DL.sizeof("L5"))
	data.struct!("LLLLL", :id, :attrs, :size_low, :size_high, :name_size)

	# allocate memories for references to long values used in backupRead().
	context = DL.malloc(DL.sizeof("L"))
	lval = DL.malloc(DL.sizeof("L"))

	while( backupRead(h, data, data.size, lval, false, false, context) )
	  size = data[:size_low] + (data[:size_high] << (DL.sizeof("I") * 8))
	  case data[:id]
	  when BACKUP_ALTERNATE_DATA
	    stream_name = DL.malloc(data[:name_size])
	    backupRead(h, stream_name, stream_name.size,
		       lval, false, false, context)
	    name = stream_name[0, stream_name.size]
	    name.tr!("\000","")
	    if( name =~ /^:(.*?):.*$/ )
	      status.push([$1,size])
	    end
	  when BACKUP_DATA
	    status.push([nil,size])
	  else
	    raise(RuntimeError, "unknown data type #{data[:id]}.")
	  end
	  l1 = DL.malloc(DL.sizeof("L"))
	  l2 = DL.malloc(DL.sizeof("L"))
	  if( !backupSeek(h, data[:size_low], data[:size_high], l1, l2, context) )
	    break
	  end
	end
      ensure
	backupRead(h, nil, 0, lval, true, false, context)
	closeHandle(h)
      end
      return status
    else
      raise(RuntimeError, "can't open #{filename}.\n")
    end
  end
end

ARGV.each{|filename|
  if( File.exist?(filename) )
    NTFS.streams(filename).each{|name,size|
      if( name )
	print("#{filename}:#{name}\t#{size}bytes\n")
      else
	print("#{filename}\t#{size}bytes\n")
      end
    }
  end
}
