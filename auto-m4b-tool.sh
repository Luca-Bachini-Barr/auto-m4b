#!/bin/bash

# Log the start of the script
echo "auto-m4b-tool.sh started at $(date)" >> /config/service.log

# set m to 1
m=1
#variable defenition
inputfolder="${INPUT_FOLDER:-"/temp/merge/"}"
outputfolder="${OUTPUT_FOLDER:-"/temp/untagged/"}"
originalfolder="${ORIGINAL_FOLDER:-"/temp/recentlyadded/"}"
fixitfolder="${FIXIT_FOLDER:-"/temp/fix"}"
backupfolder="${BACKUP_FOLDER:-"/temp/backup/"}"
binfolder="${BIN_FOLDER:-"/temp/delete/"}"
m4bend=".m4b"
logend=".log"

# --- Notifiarr notification function ---
send_notifiarr() {
  local title="$1"
  local description="$2"
  local color="$3"
  local emoji="$4"
  local image_url="$5"   # <-- new parameter for artwork URL
  local url="https://notifiarr.com/api/v1/notification/passthrough/4aa282ef-0f88-4ac6-a826-73cc352cb7e6"
  local channel_id="1411881120093442131"

  curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "{
      \"notification\": {
        \"update\": false,
        \"name\": \"auto-m4b-tool\"
      },
      \"discord\": {
        \"color\": \"$color\",
        \"images\": {
          \"thumbnail\": \"$image_url\",
          \"image\": \"\"
        },
        \"text\": {
          \"title\": \"${emoji:+$emoji }$title\",
          \"content\": \"\",
          \"description\": \"$description\",
          \"fields\": [],
          \"footer\": \"\"
        },
        \"ids\": {
          \"channel\": $channel_id
        }
      }
    }"
}

# Get duration of an audio file in seconds
get_audio_duration() {
local file="$1"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file"
}

echo "Ensuring Folder Created: $inputfolder"

#ensure the expected folder-structure
mkdir -p "$inputfolder"
mkdir -p "$outputfolder"
mkdir -p "$originalfolder"
mkdir -p "$fixitfolder"
mkdir -p "$backupfolder"
mkdir -p "$binfolder"

#fix of the user for the new created folders
username="$(whoami)"
userid="$(id -u $username)"
groupid="$(id -g $username)"
chown -R $userid:$groupid /temp 

#adjust the number of cores depending on the ENV CPU_CORES
if [ -z "$CPU_CORES" ]
then
      echo "Using all CPU cores as not other defined."
      CPUcores=$(nproc --all)
else
      echo "Using $CPU_CORES CPU cores as defined."
      CPUcores="$CPU_CORES"
fi

#adjust the interval of the runs depending on the ENV SLEEPTIME
if [ -z "$SLEEPTIME" ]
then
      echo "Using standard 1 min sleep time."
      sleeptime=1m
else
      echo "Using $SLEEPTIME min sleep time."
      sleeptime="$SLEEPTIME"
fi

echo "Changing to directory: $inputfolder FROM=$PWD"

#change to the merge folder, keeps this clear and the script could be kept inside the container
cd "$inputfolder" || return

echo "New PWD: $PWD"

# continue until $m  5
while [ $m -ge 0 ]; do

    #copy files to backup destination
    if [ "$MAKE_BACKUP" == "N" ]; then
        echo "Skipping making a backup"
    else
        echo "Making a backup of the whole $originalfolder"
        cp -Ru "$originalfolder"* $backupfolder
    fi

    #make sure all single file mp3's & m4b's are in their own folder
    echo "Making sure all books are in their own folder"
    for file in "$originalfolder"*.{m4b,mp3}; do
        if [[ -f "$file" ]]; then
            mkdir "${file%.*}"
            mv "$file" "${file%.*}"
        fi
    done

    # Finds folders with nested subfolders - renames and flattens files into a single folder
    echo "Flattening nested subfolders 3 levels deep or more and renaming files..."
    find "$originalfolder" -mindepth 3 -type f \( -name '*.mp3' -o -name '*.m4b' -o -name '*.m4a' \) -print0 | 
    while IFS= read -r -d '' file; do
            # Get the relative path from the original folder
            relative_path="${file#$originalfolder/}"
            
            # Split the path into an array
            IFS='/' read -ra path_parts <<< "$relative_path"

            # Only process if the file is at least 3 levels deep
            if [ ${#path_parts[@]} -ge 4 ]; then
                    # Get the filename (last element)
                    filename="${path_parts[-1]}"
                    
                    # Get the grandparent directory
                    grandparent="${path_parts[3]}"

                    # Construct the new filename
                    new_filename=""
                    for ((i=4; i<${#path_parts[@]}-1; i++)); do
                            new_filename+="${path_parts[i]} - "
                    done
                    new_filename+="$filename"
                    
                    # Create the new path (2 levels deep)
                    new_path="$originalfolder/$grandparent/$new_filename"
                    
                    # Create the grandparent directory if it doesn't exist
                    mkdir -p "$(dirname "$new_path")"
                    
                    # Move and rename the file
                    mv -v "$file" "$new_path"
            fi
    done

    #Move folders with multiple audiofiles to inputfolder
    echo "Moving folders with 2 or more audiofiles to $inputfolder "
    find "$originalfolder" -maxdepth 2 -mindepth 2 -type f \( -name '*.mp3' -o -name '*.m4b' -o -name '*.m4a' \) -print0 | xargs -0 -L 1 dirname | sort | uniq -c | grep -E -v '^ *1 ' | sed 's/^ *[0-9]* //' | while read i; do mv -v "$i" $inputfolder; done


    #Move single file mp3's to inputfolder
    echo "Moving single file mp3's to $inputfolder "
    find "$originalfolder" -maxdepth 2 -type f \( -name '*.mp3' \) -printf "%h\0" | xargs -0 mv -t "$inputfolder"

    #Moving the single m4b files to the untagged folder as no Merge needed
    echo "Moving all the single m4b books to $outputfolder "
    find "$originalfolder" -maxdepth 2 -type f \( -iname \*.m4b -o -iname \*.mp4 -o -iname \*.m4a -o -iname \*.ogg \) -printf "%h\0" | xargs -0 mv -t "$outputfolder"

    # clear the folders
    rm -r "$binfolder"* 2>/dev/null
    
    echo "Checking Directory $PWD"

    if ls -d */ 2>/dev/null; then
        echo Folder Detected
        for book in *; do
            if [ -d "$book" ]; then
                mpthree=$(find "$book" -maxdepth 2 -type f \( -name '*.mp3' -o -name '*.m4b' \) | head -n 1)
                m4bfile="$outputfolder$book/$book$m4bend"
                logfile="$outputfolder$book/$book$logend"
                chapters=$(ls "$inputfolder$book"/*chapters.txt 2> /dev/null | wc -l)
                if [ "$chapters" != "0" ]; then
                    echo Adjusting Chapters
                    mp4chaps -i "$inputfolder""$book"/*$m4bend
                    mv "$inputfolder$book" "$outputfolder"
                else
                    echo Sampling $mpthree
                    # --- Notifiarr: Processing started ---
				    send_notifiarr "Processing Started" "🔄 Processing of $book started." "3498db" "🔵" "$artwork_url"                    				
				    # Extract cover image (if present)
				    cover_path="/temp/artwork/cover-${book}.jpg"
				    ffmpeg -y -i "$mpthree" -an -vcodec copy "$cover_path" 2>/dev/null
				    # Build the artwork URL (assuming you mapped 4569:8080 in docker-compose)
				    artwork_url="http://localhost:8080/cover-${book}.jpg"
                    mpthree=$(find "$book" -maxdepth 2 -type f \( -name '*.mp3' -o -name '*.m4b' \) | head -n 1)
                    bit=$(ffprobe -hide_banner -loglevel 0 -of flat -i "$mpthree" -select_streams a -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1)
                    echo Bitrate = $bit
                    echo The folder "$book" will be merged to "$m4bfile"
                    echo Starting Conversion
                    m4b-tool merge "$book" -n -q --audio-bitrate="$bit" --skip-cover --use-filenames-as-chapters --no-chapter-reindexing --audio-codec=libfdk_aac --jobs="$CPUcores" --output-file="$m4bfile" --logfile="$logfile"
                    mv "$inputfolder$book" "$binfolder"
                fi
                #make sure all single file m4b's are in their own folder
                echo Putting the m4b into a folder
                for file in $outputfolder*.m4b; do
                    if [[ -f "$file" ]]; then
                        mkdir "${file%.*}"
                        mv "$file" "${file%.*}"
                    fi
                done
                # Get audiobook duration and format as HH:MM:SS
                duration_seconds=$(get_audio_duration "$m4bfile")
                duration_formatted=$(printf '%02d:%02d:%02d\n' $((duration_seconds/3600)) $((duration_seconds%3600/60)) $((duration_seconds%60)))
                # --- Notifiarr: Conversion complete ---
                send_notifiarr "Conversion Complete" "✅ Finished converting $book to m4b. Duration: $duration_formatted" "2ecc71" "✅" "$artwork_url"
                echo Finished Converting
                echo Deleting duplicate mp3 audiobook folder
            fi
        done
    else
        echo No folders detected, next run $sleeptime min...
        sleep $sleeptime
    fi
done

# Log the end of the script
echo "auto-m4b-tool.sh ended at $(date)" >> /config/service.log