#!/bin/sh

RUBYDIR=/home/ftp/pub/ruby
EXTS=.tar.gz .tar.bz2 .zip

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
  dir="${RUBYDIR}/$xy"
  echo "$dir"
  mkdir -p $dir
  for ext in (.tar.gz .tar.bz2 .zip)
  do
    cp $r$ext $dir/$r$ext
    ln -s $xy/$r$ext ${RUBYDIR}/$r$ext
    ln -s $xy/$r$ext ${RUBYDIR}/ruby-$xy-stable$ext
  done
done
