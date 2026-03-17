#!/bin/bash

# Define directories
TARGET_DIR="$HOME/.bashrc.d"
SOURCE_DIR="./modules"

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

echo "========================================"
echo "   Dynamic Alias & Function Setup       "
echo "========================================"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Directory '$SOURCE_DIR' not found."
    echo "Please run this script from the directory containing '$SOURCE_DIR'."
    exit 1
fi

# Loop through all .sh files in the available_modules folder
for module_path in "$SOURCE_DIR"/*.sh; do
    # Break if no .sh files are found
    [ -e "$module_path" ] || { echo "No .sh files found in $SOURCE_DIR."; break; }
    
    module_file=$(basename "$module_path")
    
    # Dynamically parse the file to show what commands it provides
    cmds=$(grep -E "^alias |^[a-zA-Z0-9_-]+\(\) \{" "$module_path" | sed -E 's/^alias ([^=]+)=.*/\1/; s/^([a-zA-Z0-9_-]+)\(\) \{.*/\1/' | paste -sd ", " -)
    
    echo ""
    echo -e "\033[1;36mModule:\033[0m $module_file"
    [ -n "$cmds" ] && echo -e "Provides: \033[1;33m$cmds\033[0m"
    
    # Prompt the user
    read -p "Install $module_file? [Y/n] " choice
    case "$choice" in 
        n|N ) 
            echo "Skipping $module_file." 
            ;;
        * )
            cp "$module_path" "$TARGET_DIR/$module_file"
            echo -e "\033[1;32m-> Installed $module_file to $TARGET_DIR\033[0m"
            ;;
    esac
done

echo ""
echo "Done! Reloading shell..."
exec bash
