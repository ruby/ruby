shell.rbユーザガイド
				$Release Version: 0.6.0 $
			   	$Revision$
			   	$Date$
			   	by Keiju ISHITSUKA(keiju@ishitsuka.com)

* What's shell.rb?

It realizes a wish to do execution of command and filtering like
sh/csh. However, Control statement which include sh/csh just uses
facility of ruby.

* Main classes
** Shell

All shell objects have a each unique current directory. Any shell object
execute a command on relative path from current directory.

+ Shell#cwd/dir/getwd/pwd current directory
+ Shell#system_path	  command path
+ Shell#umask		  umask

** Filter

Any result of command exection is a Filter. Filter include Enumerable,
therefore a Filter object can use all Enumerable facility.

* Main methods
** Command definition

For executing a command on OS, you need to define it as a Shell
method.  

notice) Also, there are a Shell#system alternatively to execute the
command even if it is not defined.

+ Shell.def_system_command(command, path = command)
Register command as a Shell method 

++ Shell.def_system_command "ls"
   define ls
++ Shell.def_system_command "sys_sort", "sort"
   define sys_sort as sort

+ Shell.install_system_commands(pre = "sys_")

Define all command of default_system_path. Default action prefix
"sys_" to the method name.

** 生成

+ Shell.new
Shell creates a Shell object of which current directory is the process
current directory.

+ Shell.cd(path)
Shell creates a Shell object of which current directory is <path>.

** Process management

+ jobs
The shell returns jobs list of scheduling.

+ kill sig, job
The shell kill <job>.

** Current directory operation

+ Shell#cd(path, &block)/chdir
The current directory of the shell change to <path>. If it is called
with an block, it changes current directory to the <path> while its
block executes.

+ Shell#pushd(path = nil, &block)/pushdir

The shell push current directory to directory stack. it changes
current directory to <path>. If the path is omitted, it exchange its
current directory and the top of its directory stack. If it is called
with an block, it do `pushd' the <path> while its block executes.

+ Shell#popd/popdir
The shell pop a directory from directory stack, and its directory is
changed to current directory.

** ファイル/ディレクトリ操作

+ Shell#foreach(path = nil, &block)
Same as:
  File#foreach (when path is a file)
  Dir#foreach (when path is a directory)

+ Shell#open(path, mode)
Same as:
 File#open(when path is a file)
 Dir#open(when path is a directory)

+ Shell#unlink(path)
Same as:
 Dir#open(when path is a file)
 Dir#unlink(when path is a directory)

+ Shell#test(command, file1, file2)/Shell#[command, file1, file]
Same as file testing function test().
ex)
    sh[?e, "foo"]
    sh[:e, "foo"]
    sh["e", "foo"]
    sh[:exists?, "foo"]
    sh["exists?", "foo"]

+ Shell#mkdir(*path)
Same as Dir.mkdir(its parameters is one or more)

+ Shell#rmdir(*path)
Same as Dir.rmdir(its parameters is one or more)

** Command execution
+ System#system(command, *opts)
The shell execure <command>.
ex)
  print sh.system("ls", "-l")
  sh.system("ls", "-l") | sh.head > STDOUT

+ System#rehash
The shell do rehash.

+ Shell#transact &block
The shell execute block as self.
ex)
  sh.transact{system("ls", "-l") | head > STDOUT}

+ Shell#out(dev = STDOUT, &block)
The shell do transact, and its result output to dev.

** Internal Command
+ Shell#echo(*strings)
+ Shell#cat(*files)
+ Shell#glob(patten)
+ Shell#tee(file)

When these are executed, they return a filter object, which is a
result of their execution.

+ Filter#each &block
The shell iterate with each line of it.

+ Filter#<(src)
The shell inputs from src. If src is a string, it inputs from a file
of which name is the string. If src is a IO, it inputs its IO.

+ Filter#>(to)
The shell outputs to <to>. If <to> is a string, it outputs to a file
of which name is the string. If <to>c is a IO, it outoputs to its IO.

+ Filter#>>(to)
The shell appends to <to>. If <to> is a string, it is append to a file
of which name is the string. If <to>c is a IO, it is append to its IO.

+ Filter#|(filter)
pipe combination

+ Filter#+(filter)
filter1 + filter2 output filter1, and next output filter2.

+ Filter#to_a
+ Filter#to_s

** Built-in command

+ Shell#atime(file)
+ Shell#basename(file, *opt)
+ Shell#chmod(mode, *files)
+ Shell#chown(owner, group, *file)
+ Shell#ctime(file)
+ Shell#delete(*file)
+ Shell#dirname(file)
+ Shell#ftype(file)
+ Shell#join(*file)
+ Shell#link(file_from, file_to)
+ Shell#lstat(file)
+ Shell#mtime(file)
+ Shell#readlink(file)
+ Shell#rename(file_from, file_to)
+ Shell#split(file)
+ Shell#stat(file)
+ Shell#symlink(file_from, file_to)
+ Shell#truncate(file, length)
+ Shell#utime(atime, mtime, *file)

These have a same function as a class method which is in File with same name.

+ Shell#blockdev?(file)
+ Shell#chardev?(file)
+ Shell#directory?(file)
+ Shell#executable?(file)
+ Shell#executable_real?(file)
+ Shell#exist?(file)/Shell#exists?(file)
+ Shell#file?(file)
+ Shell#grpowned?(file)
+ Shell#owned?(file)
+ Shell#pipe?(file)
+ Shell#readable?(file)
+ Shell#readable_real?(file)
+ Shell#setgid?(file)
+ Shell#setuid?(file)
+ Shell#size(file)/Shell#size?(file)
+ Shell#socket?(file)
+ Shell#sticky?(file)
+ Shell#symlink?(file)
+ Shell#writable?(file)
+ Shell#writable_real?(file)
+ Shell#zero?(file)

These have a same function as a class method which is in FileTest with
same name. 

+ Shell#syscopy(filename_from, filename_to)
+ Shell#copy(filename_from, filename_to)
+ Shell#move(filename_from, filename_to)
+ Shell#compare(filename_from, filename_to)
+ Shell#safe_unlink(*filenames)
+ Shell#makedirs(*filenames)
+ Shell#install(filename_from, filename_to, mode)

These have a same function as a class method which is in FileTools
with same name.

And also, alias:

+ Shell#cmp	<- Shell#compare
+ Shell#mv	<- Shell#move
+ Shell#cp	<- Shell#copy
+ Shell#rm_f	<- Shell#safe_unlink
+ Shell#mkpath	<- Shell#makedirs

* Samples
** ex1

  sh = Shell.cd("/tmp")
  sh.mkdir "shell-test-1" unless sh.exists?("shell-test-1")
  sh.cd("shell-test-1")
  for dir in ["dir1", "dir3", "dir5"]
    if !sh.exists?(dir)
      sh.mkdir dir
      sh.cd(dir) do
	f = sh.open("tmpFile", "w")
	f.print "TEST\n"
	f.close
      end
      print sh.pwd
    end
  end

** ex2

  sh = Shell.cd("/tmp")
  sh.transact do
    mkdir "shell-test-1" unless exists?("shell-test-1")
    cd("shell-test-1")
    for dir in ["dir1", "dir3", "dir5"]
      if !exists?(dir)
	mkdir dir
	cd(dir) do
	  f = open("tmpFile", "w")
	  f.print "TEST\n"
	  f.close
	end
	print pwd
      end
    end
  end

** ex3

  sh.cat("/etc/printcap") | sh.tee("tee1") > "tee2"
  (sh.cat < "/etc/printcap") | sh.tee("tee11") > "tee12"
  sh.cat("/etc/printcap") | sh.tee("tee1") >> "tee2"
  (sh.cat < "/etc/printcap") | sh.tee("tee11") >> "tee12"

** ex5

  print sh.cat("/etc/passwd").head.collect{|l| l =~ /keiju/}

