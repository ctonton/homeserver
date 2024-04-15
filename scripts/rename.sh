#!/bin/bash
PS3="Select directory to process: "
select vid in movie show
do
  case $vid in
    movie)
      cd $vid
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
      chmod -R 777 *
      chown -R nobody:nogroup *
      mv -f A* ../../../Movies/"A movies"/
      mv -f B* ../../../Movies/"B movies"/
      mv -f C* ../../../Movies/"C movies"/
      mv -f D* ../../../Movies/"D movies"/
      mv -f E* ../../../Movies/"E movies"/
      mv -f F* ../../../Movies/"F movies"/
      mv -f G* ../../../Movies/"G movies"/
      mv -f H* ../../../Movies/"H movies"/
      mv -f I* ../../../Movies/"I movies"/
      mv -f J* ../../../Movies/"J movies"/
      mv -f K* ../../../Movies/"K movies"/
      mv -f L* ../../../Movies/"L movies"/
      mv -f M* ../../../Movies/"M movies"/
      mv -f N* ../../../Movies/"N movies"/
      mv -f O* ../../../Movies/"O movies"/
      mv -f P* ../../../Movies/"P movies"/
      mv -f Q* ../../../Movies/"Q movies"/
      mv -f R* ../../../Movies/"R movies"/
      mv -f S* ../../../Movies/"S movies"/
      mv -f T* ../../../Movies/"T movies"/
      mv -f U* ../../../Movies/"U movies"/
      mv -f V* ../../../Movies/"V movies"/
      mv -f W* ../../../Movies/"W movies"/
      mv -f X* ../../../Movies/"X movies"/
      mv -f Y* ../../../Movies/"Y movies"/
      mv -f Z* ../../../Movies/"Z movies"/
      mv -f * ../../../Movies/"00 movies"/
      cd ..
      break;;
    show)
      cd $vid
      for dir in "A "*
      do
        mv "$dir" "$(echo $dir | sed 's/^A //'), A"
      done
      for dir in "An "*
      do
        mv "$dir" "$(echo $dir | sed 's/^An //'), An"
      done
      for dir in "The "*
      do
        mv "$dir" "$(echo $dir | sed 's/^The //'), The"
      done
      chmod -R 777 *
      chown -R nobody:nogroup *
      cp -fpru * ../../../Television/
      cd ..
      rm -rf show/*
      break;;
    *)
      echo "Invalid Selection.";;
  esac
done
exit
