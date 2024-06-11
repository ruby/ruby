# Creates a temporary directory in the current working directory
# for temporary files created while running the specs. All specs
# should clean up any temporary files created so that the temp
# directory is empty when the process exits.

SPEC_TEMP_DIR_PID = Process.pid

if spec_temp_dir = ENV["SPEC_TEMP_DIR"]
  spec_temp_dir = File.realdirpath(spec_temp_dir)
else
  spec_temp_dir = "#{File.realpath(Dir.pwd)}/rubyspec_temp/#{SPEC_TEMP_DIR_PID}"
end
SPEC_TEMP_DIR = spec_temp_dir

SPEC_TEMP_UNIQUIFIER = +"0"

at_exit do
  begin
    if SPEC_TEMP_DIR_PID == Process.pid
      Dir.delete SPEC_TEMP_DIR if File.directory? SPEC_TEMP_DIR
    end
  rescue SystemCallError
    STDERR.puts <<-EOM

-----------------------------------------------------
The rubyspec temp directory is not empty. Ensure that
all specs are cleaning up temporary files:
  #{SPEC_TEMP_DIR}
-----------------------------------------------------

    EOM
  rescue Object => e
    STDERR.puts "failed to remove spec temp directory"
    STDERR.puts e.message
  end
end

def tmp(name, uniquify = true)
  if Dir.exist? SPEC_TEMP_DIR
    stat = File.stat(SPEC_TEMP_DIR)
    if stat.world_writable? and !stat.sticky?
      raise ArgumentError, "SPEC_TEMP_DIR (#{SPEC_TEMP_DIR}) is world writable but not sticky"
    end
  else
    umask = File.umask
    if (umask & 0002) == 0 # o+w
      raise ArgumentError, "File.umask #=> #{umask.to_s(8)} (world-writable)"
    end
    mkdir_p SPEC_TEMP_DIR
  end

  if uniquify and !name.empty?
    slash = name.rindex "/"
    index = slash ? slash + 1 : 0
    name = +name
    name.insert index, "#{SPEC_TEMP_UNIQUIFIER.succ!}-"
  end

  File.join SPEC_TEMP_DIR, name
end
