#!/bin/bash
for dir in "A "*
do
  if [[ "$dir" == *" - "* ]]
  then
    mv "$dir" "$(echo $dir | sed 's/^A //' | sed 's/ -/, A -/')"
  else
    mv "$dir" "$(echo $dir | sed 's/^A //' | sed 's/ (/, A (/')"
  fi
done
for dir in "An "*
do
  if [[ "$dir" == *" - "* ]]
  then
    mv "$dir" "$(echo $dir | sed 's/^An //' | sed 's/ -/, An -/')"
  else
    mv "$dir" "$(echo $dir | sed 's/^An //' | sed 's/ (/, An (/')"
  fi
done
for dir in "The "*
do
  if [[ "$dir" == *" - "* ]]
  then
    mv "$dir" "$(echo $dir | sed 's/^The //' | sed 's/ -/, The -/')"
  else
    mv "$dir" "$(echo $dir | sed 's/^The //' | sed 's/ (/, The (/')"
  fi
done
exit
