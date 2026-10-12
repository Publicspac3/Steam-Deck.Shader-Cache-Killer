#!/bin/bash
#Steam Deck Shader Cache Killer by scawp
#License: DBAD: https://github.com/scawp/Steam-Deck.Shader-Cache-Killer/blob/main/LICENSE.md
#Source: https://github.com/Publicspac3/Steam-Deck.Shader-Cache-Killer
# Use at own Risk!

live=1
if [ "$1" = "dry-run" ]; then
  live=0
fi

#live=0 #uncomment for debugging/testing

#script_dir="$(dirname $(realpath "$0"))"
#conf_dir="$(dirname $(realpath "$0"))/config"
conf_dir="/tmp/scawp.SDCacheKiller"
tmp_dir="/tmp/scawp.SDCacheKiller"
steamapps_dir="/home/$USER/.local/share/Steam/steamapps"

#create tempory directory
mkdir -p "$tmp_dir"
mkdir -p "$conf_dir"

#check we can find the steamapps directory
if [ ! -d "$steamapps_dir" ]; then
  zenity --error --width=400 \
  --text="Cannot find $steamapps_dir, Quitting!"
  exit 1;
fi

#find all of the steam library locations

steamapp_dir=( $(grep -ho '\"path\"\s*\".*\"' "$steamapps_dir/libraryfolders.vdf" | sed -e 's/^\"path\"\s*\"//' -e 's/\"$/\/steamapps/') )

echo "Found libraryfolders.vdf and $echo("${#steamapp_dir[@]}") install locations at $steamapps_dir"
echo "Found libraries at:"
for dir in "${steamapp_dir[@]}";
do
  echo ${dir}
done

function get_list () {

  #This function mostly just merges .txt files to get to tmp_merged2.txt then removes the proton entry
  #It iterates through the drives, grabs the ids, paths, caches, etc and puts it in one big merged file.
  for dir in "${steamapp_dir[@]}";
  do

    true > "$tmp_dir/tmp_list.txt"

    #Grabs size of shader cache path and path itself tmp_list2.txt
    du -m --max-depth 0  "$dir/$1"/* | sort -nr > "$tmp_dir/tmp_list2.txt"
    
    #Check for symlinked folders
    while read -r path; do
      if [ -h $path ] && [ ! -e $path ]; then
        echo -e "?\t$(readlink $path)" >> "$tmp_dir/tmp_list.txt"
      else
        du -m --max-depth 0  "$(realpath $path)" >> "$tmp_dir/tmp_list.txt"

      fi
    done <<< "$(awk '{ print $2 }' "$tmp_dir/tmp_list2.txt")"

    #Games ids in tmp_ids.txt
    du -m --max-depth 0  "$dir/$1"/* | sort -nr | sed 's/^.*\///' > "$tmp_dir/tmp_ids.txt"

    #.acf file location strings in tmp_col_manifest.txt
    du -m --max-depth 0  "$dir/$1"/* | sort -nr | sed -e 's/^.*\///' -e 's/^/appmanifest_/' -e 's/$/\.acf/' > "$tmp_dir/tmp_col_manifest.txt"

    true > "$tmp_dir/tmp_names.txt"

    while read -r manifest; do
      found=0
      app_id="$(echo "$manifest" | sed -e "s/appmanifest_//" -e "s/\.acf//")"

      echo "Found app id $app_id"

      for dir in "${steamapp_dir[@]}";
      do
        if [ -s  "$dir/$manifest" ]; then
          echo  "dir/manifest is $dir/$manifest"
          install_dir="$(grep -ho "\"installdir\"\s*\".*\"" "$dir/$manifest" | sed -e 's/^\"installdir\"\s*\"//' -e 's/\"$//')"
          echo "install_dir (game name) is $install_dir"

          echo -e "$install_dir\t " >> "$tmp_dir/tmp_names.txt"
          found=1
          
          break;
        fi
      done

      if [ $found = 0 ]; then
        #Non-steam games might be found by checking the controller_ui.txt logs
        app_id="$(echo "$manifest" | sed -e "s/appmanifest_//" -e "s/\.acf//")"
        find_in_log="$(grep -ri "AppID\s$app_id," ~/.local/share/Steam/logs/controller_ui.txt | tail -n 1)"
        
        if [ ! -z "$find_in_log" ];then
        echo -e "$find_in_log\tNon-Steam" | sed -e "s/.*,\s//" >> "$tmp_dir/tmp_names.txt"
        else
          #try in content_log.txt also
          find_in_log="$(grep -ri "SteamLaunch\sAppId=$app_id" ~/.local/share/Steam/logs/content_log.txt | tail -n 1)"
          if [ ! -z "$find_in_log" ];then
            echo -e "$find_in_log\tNon-Steam" | sed -e "s/.*[=|\/]//g" -e "s/\"//g" >> "$tmp_dir/tmp_names.txt"
          else
            #we don't know
            echo -e "Unknown\tNon-Steam" >> "$tmp_dir/tmp_names.txt"
          fi
        fi
      fi
    done < "$tmp_dir/tmp_col_manifest.txt"

    paste "$tmp_dir/tmp_list.txt" "$tmp_dir/tmp_ids.txt" "$tmp_dir/tmp_names.txt" | sed -e 's/^/FALSE\t/' >> "$tmp_dir/tmp_merged.txt"

    awk -F '\t' '{ print $1"\t"$2"\t"$4"\t"$5"\t"$6"\t"$3 }' "$tmp_dir/tmp_merged.txt" > "$tmp_dir/tmp_merged2.txt"

    #Remove duplicate entries 
    awk -i inplace '!seen[$0]++' $tmp_dir/tmp_merged2.txt

    #Don't list Proton, deleting them is Garbage Day
    sed -i '/Proton/d' "$tmp_dir/tmp_merged2.txt"

  done
  
}

function gui () {
  IFS=$'[\t|\n]';
  selected_caches=$(zenity --list --title="Select $1 for Deletion" \
    --width=1200 --height=720 --print-column=6 --separator="\t" \
    --ok-label "Delete selected $1!" --extra-button "$2" \
    --checklist --column="check" --column="Size (MB)" --column="App Id" --column="Name" --column="Info" --column="Real Path" \
    $(cat "$tmp_dir/tmp_merged2.txt"))
  ret_value="$?"
  unset IFS;
}

function main () {
  get_list $1 $2
  gui $1 $2

  if [ "$ret_value" = 1 ]; then
    if [ "$selected_caches" = "compatdata" ]; then
      main "compatdata" "shadercache"
    else
      if [ "$selected_caches" = "shadercache" ]; then
        main "shadercache" "compatdata"
      else  
        exit;
      fi
    fi
  fi

  IFS=$'\t'; selected_cache_array=($selected_caches); unset IFS;
  i=0

  if [ "${#selected_cache_array[@]}" = 0 ]; then
    zenity --error --width=400 \
    --text="No $1 Selected, Quitting!"
    exit 1;
  fi

  if [ "$1" = "compatdata" ]; then
    zenity --question --width=400 \
    --text="Warning!\nDeleting compactdata will break the game!\nDeleting compactdata for a  Proton version will break Proton!\nCheck appIds on steamdb if in doubt!\nContinue at own risk!"

    if [ "$?" = 1 ]; then
      exit 1;
    fi
  fi

  (
    for selected_cache in "${selected_cache_array[@]}"; do
      ((i++))
      echo "# Killing $selected_cache";
      ((percentage=($i*100/${#selected_cache_array[@]})))

      if [ $live = 1 ]; then
        rm -r "$selected_cache"
      fi

      echo "$percentage"; 
      #delay progress bar a little
      sleep 1
    done
    if [ $live = 1 ]; then
      echo "# $1 Killed!"
    else
      echo "# $1 Dry-Run nothing deleted!"
    fi
  ) | zenity --progress --width=400 \
    --title="Deleting $1 Dir" \
    --percentage=0

  if [ "$?" = 1 ] ; then
    zenity --error --width=400 \
      --text="User Cancelled, some Cache not cleared!"
    exit 1;
  fi

  exit 0;
}

main "shadercache" "compatdata"
