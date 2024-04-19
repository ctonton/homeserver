#!/bin/bash

function rename {
  for title in "A "*
  do
    if [[ "$title" == *" - "* ]]
    then
      mv "$title" "$(echo $title | sed 's/^A //' | sed 's/ -/, A -/')"
    else
      mv "$title" "$(echo $title | sed 's/^A //' | sed 's/ (/, A (/')"
    fi
  done
  for title in "An "*
  do
    if [[ "$title" == *" - "* ]]
    then
      mv "$title" "$(echo $title | sed 's/^An //' | sed 's/ -/, An -/')"
    else
      mv "$title" "$(echo $title | sed 's/^An //' | sed 's/ (/, An (/')"
    fi
  done
  for title in "The "*
  do
    if [[ "$title" == *" - "* ]]
    then
      mv "$title" "$(echo $title | sed 's/^The //' | sed 's/ -/, The -/')"
    else
      mv "$title" "$(echo $title | sed 's/^The //' | sed 's/ (/, The (/')"
    fi
  done
  chmod -R 777 *
  chown -R nobody:nogroup *
}

PS3="Select directory to process: "
select media in movie show
do
  case $media in
    movie)
      cd movie
      rename
      for title in *
      do
        alpha=$(echo $title | cut -c 1)
        if [[ $alpha == [0-9] ]]
        then
          alpha="00"
        fi
        dest="../../../Movies/$alpha movies"
        if [ -e "$dest"/"$title"/ ]
        then
          rm -rf "$dest"/"$title"
        fi
        mv -f "$title" "$dest"/
      done
      cd ..
      break;;
    show)
      cd show
      rename
      cp -fpru * ../../../Television/
      cd ..
      rm -rf show/*
      break;;
    *)
      echo "Invalid Selection.";;
  esac
done
exit
