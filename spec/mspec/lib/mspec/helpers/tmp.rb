# Creates a temporary directory in the current working directory
# for temporary files created while running the specs. All specs
# should clean up any temporary files created so that the temp
# directory is empty when the process exits.

SPEC_TEMP_DIR_PID = Process.pid
SPEC_TEMP_DIR_LIST = []
if tmpdir = ENV['SPEC_TEMP_DIR']
  temppath = File.expand_path(tmpdir) + "/"
else
  tmpdir = File.expand_path("rubyspec_temp")
  temppath = tmpdir + "/#{SPEC_TEMP_DIR_PID}"
  SPEC_TEMP_DIR_LIST << tmpdir
end
SPEC_TEMP_DIR_LIST << temppath
SPEC_TEMP_DIR = temppath
SPEC_TEMP_UNIQUIFIER = "0"

at_exit do
  begin
    if SPEC_TEMP_DIR_PID == Process.pid
      while temppath = SPEC_TEMP_DIR_LIST.pop
        next unless File.directory? temppath
        Dir.delete temppath
      end
    end
  rescue SystemCallError
    STDERR.puts <<-EOM

-----------------------------------------------------
The rubyspec temp directory is not empty. Ensure that
all specs are cleaning up temporary files:
  #{temppath}
-----------------------------------------------------

    EOM
  rescue Object => e
    STDERR.puts "failed to remove spec temp directory"
    STDERR.puts e.message
  end
end

def tmp(name, uniquify = true)
  mkdir_p SPEC_TEMP_DIR unless Dir.exist? SPEC_TEMP_DIR

  if uniquify and !name.empty?
    slash = name.rindex "/"
    index = slash ? slash + 1 : 0
    name.insert index, "#{SPEC_TEMP_UNIQUIFIER.succ!}-"
  end

  File.join SPEC_TEMP_DIR, name
end
