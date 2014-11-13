require "rbconfig"

module EnvUtil
  def find_executable(cmd, *args)
    exts = RbConfig::CONFIG["EXECUTABLE_EXTS"].split | [RbConfig::CONFIG["EXEEXT"]]
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      next if path.empty?
      path = File.join(path, cmd)
      exts.each do |ext|
        cmdline = [path + ext, *args]
        begin
          return cmdline if yield(IO.popen(cmdline, "r", err: [:child, :out], &:read))
        rescue
          next
        end
      end
    end
    nil
  end
  module_function :find_executable
end
