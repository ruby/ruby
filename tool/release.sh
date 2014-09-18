#!/bin/sh

RUBYDIR=/home/ftp/pub/ruby
EXTS='.tar.gz .tar.bz2 .tar.xz .zip'

releases=`ls ruby-*|grep -o 'ruby-[0-9]\.[0-9]\.[0-9]\(-\(preview\|rc\|p\)[0-9]\{1,4\}\)\?'|uniq`

# check files
for r in $releases
do
  echo "checking files for $r..."
  for ext in $EXTS
  do
    if ! [ -f $r$ext ];then
      echo "ERROR: $r$ext not found"
      exit 1
    fi
  done
  echo "files are ok"
done

# version directory
for r in $releases
do
  xy=`echo $r|grep -o '[0-9]\.[0-9]'`
  preview=`echo $r|grep -o -- '-\(preview\|rc\)'`
  dir="${RUBYDIR}/$xy"
  echo "$dir"
  mkdir -p $dir
  for ext in $EXTS
  do
    cp $r$ext $dir/$r$ext
    ln -sf $xy/$r$ext ${RUBYDIR}/$r$ext
    if [ x$preview = x ];then
      ln -sf $xy/$r$ext ${RUBYDIR}/ruby-$xy-stable$ext
    fi
  done
done
