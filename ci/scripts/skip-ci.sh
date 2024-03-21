#!/bin/bash

function skip_ci() {
    local ignore_list="$1"
    local changed_files="$2"
    while read -r changed_file
    do
        while read -r skip_for
        do
            # If a directory is on the allow-list
            if [ -d "$skip_for" ]; then
                for file_in_dir in "$skip_for"/*; do
                    if [ "$file_in_dir" == "$changed_file" ]; then
                        continue 3
                    fi
                done
            fi
            if [ "$skip_for" == "$changed_file" ] ; then
                continue 2
            fi
        done < "$ignore_list"
        # If we get here the file is not skipped or in a skipped dir.
        return 1
    done < "$changed_files"
    # If we get here, all files are skipped or in skipped dirs.
    return 0
}
