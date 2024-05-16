#!/bin/bash
if ! dpkg -s ffmpeg >/dev/null 2>&1
then
  sudo apt update
  sudo apt install -y ffmpeg
fi
shopt -s extglob

function convert {
for mp4 in *.mp4
do
  if ffprobe -i "$mp4" -hide_banner 2>&1 | grep -q 'Subtitle:'
  then
    ffmpeg -i "$mp4" -hide_banner -map 0:s:0 "${mp4%.*}".srt
  fi
  mv "$mp4" old.mp4
  ffmpeg -i old.mp4 -hide_banner -c:a copy -c:v copy -sn -map_metadata -1 -map_chapters -1 -movflags faststart "$mp4"
  rm -f old.mp4
done
for mkv in *.mkv
do
  if ffprobe -i "$mkv" -hide_banner 2>&1 | grep -q 'Subtitle:'
  then
    ffmpeg -i "$mkv" -hide_banner -map 0:s:0 "${mkv%.*}".srt
  fi
  ffmpeg -i "$mkv" -hide_banner -c:a copy -c:v copy -sn -map_metadata -1 -map_chapters -1 -movflags faststart "${mkv%.*}".mp4
  rm -f "$mkv"
done
rm -rf !(*.mp4|*.srt)
}

PS3="Select directory to process: "
select media in movie show
do
  case $media in
    movie)
      cd movie
      for title in */
      do
        cd "$title"
        convert
        cd ..
      done
      cd ..
      break;;
    show)
      cd show
      for title in */
      do
        cd "$title"
        for season in */
        do
          cd "$season"
          convert
          cd ..
        done
        cd ..
      done
      cd ..
      break;;
    *)
      echo "Invalid Selection.";;
  esac
done
exit
