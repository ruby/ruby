BEGIN {
  if errout = ARGV.shift
    dir = File.dirname(File.expand_path(__FILE__))
    basename = File.basename(__FILE__)
    require "#{dir}/envutil"
    STDERR.reopen(File.open(errout, "w"))
    STDERR.sync = true
    Dir.chdir(dir)
    cmd = "\"#{EnvUtil.rubybin}\" \"#{basename}\""
    exec(cmd)
    exit!("must not reach here")
  end
}

def end1
  END {}
end

end1

eval <<EOE
  def end2
    END {}
  end
EOE

