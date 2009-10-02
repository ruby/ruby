module FileCreation
  OLDFILE = "testdata/old"
  NEWFILE = "testdata/new"

  def create_timed_files(oldfile, *newfiles)
    return if File.exist?(oldfile) && newfiles.all? { |newfile| File.exist?(newfile) }
    old_time = create_file(oldfile)
    newfiles.each do |newfile|
      while create_file(newfile) <= old_time
        sleep(0.1)
        File.delete(newfile) rescue nil
      end
    end
  end

  def create_dir(dirname)
    FileUtils.mkdir_p(dirname) unless File.exist?(dirname)
    File.stat(dirname).mtime
  end

  def create_file(name)
    create_dir(File.dirname(name))
    FileUtils.touch(name) unless File.exist?(name)
    File.stat(name).mtime
  end

  def delete_file(name)
    File.delete(name) rescue nil
  end
end
