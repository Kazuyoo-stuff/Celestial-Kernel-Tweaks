#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

# fucntion to preload item @reljawa
  preload_item() {
    local file="$1"
    
    if [[ -e "$file" ]]; then
      if [[ -z "$LD_PRELOAD" ]]; then
        export LD_PRELOAD="$file"
      else
        export LD_PRELOAD="$LD_PRELOAD:$file"
      fi
      
      echo "Preloaded: $file"
      echo ""
      return 0
    else
      echo "Failed to preload: $file"
      echo ""
      return 1
    fi
  }

  # Helper function to check if a directory is empty
  is_directory_empty() {
    if [[ -z "$(ls -A "$1" 2>/dev/null)" ]]; then
      return 0
    else
      return 1
    fi
  }

  # Preload EGL Libraries
  egl_libs=(/system/vendor/lib/egl/*)

  # Preload items using for loop with background processes
  for item in "${egl_libs[@]}"; do
    if is_directory_empty "$item"; then
      continue
    fi
    preload_item "$item" &
  done

  # Check system architecture
  if [[ $(getconf LONG_BIT) -eq 32 ]]; then
    hw_libs=(/system/lib32/hw/*)
  else
    hw_libs=(/system/lib64/hw/*)
  fi

  # Preload hardware libraries using for loop with background processes
  for item in "${hw_libs[@]}"; do
    if is_directory_empty "$item"; then
      continue
    fi
    preload_item "$item" &
  done

  # Preload graphics and hidl libraries based on system architecture
  if [[ $(getconf LONG_BIT) -eq 32 ]]; then
    graphics_files=$(find /system/lib32 -name "graphics" 2>/dev/null)
  else
    graphics_files=$(find /system/lib64/* -name "android.graphics" 2>/dev/null)
  fi

  # Preload graphics files using for loop with background processes
  for item in $graphics_files; do
    preload_item "$item" || continue
  done

# This script will be executed in post-fs-data mode