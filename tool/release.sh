#!/bin/sh

RUBYDIR=/home/ftp/pub/ruby

releases=`ls ruby-*|grep -o 'ruby-[0-9]\.[0-9]\.[0-9]\(-\(preview\|rc\|p\)[0-9]\{1,4\}\)\?'|uniq`

# check files
for r in $releases
do
  echo "checking files for $r..."
  if ! [ -f $r.tar.gz ];then
    echo "ERROR: $r.tar.gz not found"
    exit 1
  elif ! [ -f $r.tar.bz2 ];then
    echo "ERROR: $r.tar.bz2 not found"
    exit 1
  elif ! [ -f $r.zip ];then
    echo "ERROR: $r.zip not found"
    exit 1
  else
    echo "files are ok"
  fi
done

# version directory
for r in $releases
do
  xy=`echo $r|grep -o '[0-9]\.[0-9]'`
  dir="${RUBYDIR}/$xy"
  echo "$dir"
  mkdir -p $dir
  cp $r.tar.gz $dir/$r.tar.gz
  cp $r.tar.bz2 $dir/$r.tar.bz2
  cp $r.zip $dir/$r.zip
done
