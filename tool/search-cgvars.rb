#
# Listing C's global variables in .so or .o, or .bundle on Mac OS using "objdump -t" (elf64-x86-64)
# to check ractor-safety.
#
# Usage: ruby search-cgvars.rb foo.so bar.o .ext/x86_64-darwin18/psych.bundle
#
MAC_OS = RbConfig::CONFIG['host_os'].match? /darwin|mac os/

def gvars file
  # '0000000000031ac8 g     O .bss   0000000000000008              rb_cSockIfaddr'
  # On mac, with .bundle files:
  # '0000000000004258 l     O __DATA,__bss  _passwd_blocking'

  strs = `objdump -t #{file}`
  found = {}
  strs.each_line{|line|
    if /[\da-f]{16} / =~ line
      addr = line[0...16]
      flags = line[17...24].tr(' ', '').split(//).sort.uniq
      rest = line[25..]
      if MAC_OS
        seg, name = rest.split(/\s+/)
      else
        seg, size, name = rest.split(/\s+/)
      end
      if flags.include?('O')
        # p [addr, flags, seg, size, name]
        found[name] = [flags, seg, *size]
      end
    end
  }
  puts "## #{file}:"
  found.sort_by{|name, (flags, *)|
    [flags, name]
  }.each{|name, rest|
    flags, seg, size = *rest
    next if (size.to_i == 0 && !MAC_OS) && seg != '*UND*'
    case seg
    when ".rodata", ".data.rel.ro", ".got.plt", ".eh_frame", ".fini_array"
      next
    when /,__const$/ # Mac OS
      next
    end
    case name
    when /^id_/, /^rbimpl_id/, /^sym_/, /^rb_[cme]/, /\Acompleted\.\d+\z/
      next
    when /^_id_/, /\.rbimpl_id(\.\d+)?$/ # Mac OS
      next
    end
    puts "  %40s %s" % [name, rest.inspect]
  }
end
ARGV.each{|file|
  gvars file
}
