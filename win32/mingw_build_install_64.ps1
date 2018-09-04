<# Script for building & installing MinGW Ruby for CI
Assumes C is main drive
Assumes a Ruby exe is in path
Assumes 'Git for Windows' is installed at C:\Program Files\Git
Assumes MSYS2/MinGW is installed at C:\msys64
#>

$bits = if ($args.length -eq 1 -and $args[0] -eq 32) { 32 } else { 64 }

#———————————————————————————————————————————————————————————————————— Check-Exit
# checks whether to exit
function Check-Exit($msg, $pop) {
  if ($LastExitCode -and $LastExitCode -ne 0) {
    if ($pop) { Pop-Location }
    Write-Line "Failed - $msg"
    exit 1
  }
}

#——————————————————————————————————————————————————————————————————————————— Run
# Run a command and check for error
function Run($exec) {
  Write-Line $exec
  iex $exec
  Check-Exit $exec
}

#———————————————————————————————————————————————————————————————————— Write-Line
# Write 80 dash line then msg in color $fc
function Write-Line($msg) { Write-Host "$dl`n$msg" -ForegroundColor $fc }

#———————————————————————————————————————————————————————————————— Create-Folders
# Creates build, install, and git folders at same place as ruby repo folder
function Create-Folders {
  $script:main_dir = `
    $(Resolve-Path -Path "$pwd/.."  | select -expand Path).replace('\', '/')
  
  $script:main_dir_u = $main_dir.replace("C:", "/c")

  # create (or clean) build & install
  if (Test-Path -Path $main_dir/build   -PathType Container ) {
    Remove-Item -Path $main_dir/build   -recurse
  }
  New-Item      -Path $main_dir/build   -ItemType Directory 1> $null

  if (Test-Path -Path $main_dir/install -PathType Container ) {
    Remove-Item -Path $main_dir/install -recurse
  }
  New-Item      -Path $main_dir/install -ItemType Directory 1> $null

  # create git symlink, which RubyGems seems to want
  if (!(Test-Path -Path $main_dir/git -PathType Container )) {
        New-Item  -Path $main_dir/git -ItemType SymbolicLink -Value "C:\Program Files\Git" 1> $null
  }
}

#————————————————————————————————————————————————————————————————— Set-Variables
# set base variables, including MSYS2 location and bit related varis
function Set-Variables {
  if ($bits -eq 32) {
         $script:m_arch = "i686"   ; $t_m_pre = "i686"   }
  else { $script:m_arch = "x86-64" ; $t_m_pre = "x86_64" }
  
  $script:ruby_path = $(ruby -e "puts RbConfig::CONFIG['bindir']").trim().replace('\', '/')

  $script:help_me = "HELP ME WORKS?"
  $script:mingw   = "mingw$bits"
  $script:chost   = "$t_m_pre-w64-mingw32"
  $script:m_root  = "C:/msys64"
  $script:make    = "mingw32-make.exe"

  $script:jobs    = $env:NUMBER_OF_PROCESSORS
  $script:fc      = "Yellow"
  $script:dash    = "$([char]0x2015)"
  $script:dl      = $($dash * 80)
}

#——————————————————————————————————————————————————————————————————————— Set-Env
# Set ENV, including gcc flags
function Set-Env {
  $env:MSYSTEM_PREFIX = "/$mingw"
  $env:MSYSTEM        = "$mingw".ToUpper()
  $env:MINGW_CHOST    = $chost

  $env:path = "$ruby_path;$m_root/$mingw/bin;$main_dir/git/cmd;$m_root/usr/bin;$env:path"

  $env:GIT      = "$main_dir/git/cmd/git.exe"
  $env:CFLAGS   = "-march=$m_arch -mtune=generic -O3 -pipe"
  $env:CXXFLAGS = "-march=$m_arch -mtune=generic -O3 -pipe"
  $env:CPPFLAGS = "-D_FORTIFY_SOURCE=2 -D__USE_MINGW_ANSI_STDIO=1 -DFD_SETSIZE=2048"
  $env:LDFLAGS  = "-pipe"

  $env:UNICODE_FILES = '.'
}

#——————————————————————————————————————————————————————————————————— start build
Create-Folders
Set-Variables
Set-Env

Run "sh -c `"autoreconf -fi`""

cd $main_dir/build

$args = "--build=$chost --host=$chost --target=$chost"

Run "sh -c `"../ruby/configure --disable-install-doc --prefix=/install $args`""
Run "$make -j $jobs up"
Run "$make -j $jobs"
Run "$make -f GNUMakefile DESTDIR=$main_dir_u install-nodoc"

# Standard Ruby CI doesn't run this test, remove for better comparison
$remove_test = "$main_dir/ruby/test/ruby/enc/test_case_comprehensive.rb"
if (Test-Path -Path $remove_test -PathType Leaf) { Remove-Item -Path $remove_test }

$env:path = $env:path.replace("$ruby_path;", '')
