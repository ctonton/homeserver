#!/bin/bash
shopt -s extglob
cd Public/Downloads/Working
for dir in *
do
  cd "$dir"
  for mp4 in *.mp4
  do
    if ffprobe -i "$mp4" -hide_banner 2>&1 | grep -q 'Subtitle:'
    then
      ffmpeg -i "$mp4" -hide_banner -map 0:s:0 "${mp4%.*}".srt
    fi
    mv "$mp4" old.mp4
    ffmpeg -i old.mp4 -hide_banner -c:a copy -c:v copy -sn -map_metadata -1 -map_chapters -1 -movflags faststart "$mp4"
    rm old.mp4
  done
  for mkv in *.mkv
  do
    if ffprobe -i "$mkv" -hide_banner 2>&1 | grep -q 'Subtitle:'
    then
      ffmpeg -i "$mkv" -hide_banner -map 0:s:0 "${mkv%.*}".srt
    fi
    ffmpeg -i "$mkv" -hide_banner -c:a copy -c:v copy -sn -map_metadata -1 -map_chapters -1 -movflags faststart "${mkv%.*}".mp4
  done
  rm -rf !(*.mp4|*.srt)
  cd ..
done
exit

