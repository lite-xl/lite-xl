#!/bin/bash

IFS=$'\r\n' GLOBIGNORE='*' command eval  'DIRS=($(find . -type d))'

n=${#DIRS[@]}
files=()
for i in {1..20}; do
  files[$i]="${DIRS[$(( $RANDOM % $n ))]}/dmon-test-$i.txt"
done

for name in "${files[@]}"; do
  echo "create ${name#./}"
  touch "${name#./}"
done

echo "Files created"
sleep 2;


for name in "${files[@]}"; do
  echo "remove ${name#./}"
  rm "${name#./}"
done

echo "Files removed"
