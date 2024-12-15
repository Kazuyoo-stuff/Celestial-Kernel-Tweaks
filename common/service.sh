#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
# thanks to tytydraco & notzeetaa & all developer for reference this module kernel

# Waiting for boot completed
  while [ "$(getprop sys.boot_completed | tr -d '\r')" != "1" ]; do sleep 3; done
  
# Sync to data in the rare case a device crashes
  sync

# Device online functions
  wait_until_login() {
    # whether in lock screen, tested on Android 7.1 & 10.0
    # in case of other magisk module remounting /data as RW
    while [ "$(dumpsys window policy | grep mInputRestricted=true)" != "" ]; do
        sleep 0.1
    done
    # we doesn't have the permission to rw "/sdcard" before the user unlocks the screen
    while [ ! -d "/sdcard/Android" ]; do
        sleep 1
    done
  }
  wait_until_login
  
  end () {
    su -lp 2000 -c "cmd notification post -S bigtext -t 'Celestial-Kernel-Tweak🛸' tag 'Status : Running ^-^'" >/dev/null 2>&1
  }

# Get total RAM in MB
   TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')

# Low RAM threshold (adjust as needed)
   LOW_RAM_THRESHOLD=2048  # 2GB in MB
    
# Duration in nanoseconds of one scheduling period
   SCHED_PERIOD="$((4 * 1000 * 1000))"

# How many tasks should we have at a maximum in one scheduling period
   SCHED_TASKS="6"
  
# Function to write a value to a specified file
write () {
    local file="$1"
    local value="$2"

    # Check arguments
    if [[ -z "$file" || -z "$value" ]]; then
        return 1
    fi

    # Make sure the file exists
    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Change file permissions to writable if needed
    if [[ ! -w "$file" ]]; then
        chmod +w "$file" 2>/dev/null || {
            return 1
        }
    fi

    # Write values to file
    if ! echo "$value" > "$file" 2>/dev/null; then
        echo "Failed : $1 → $2"
        return 1
    fi

	# Log the success
	echo "$1 → $2"
    return 0
}

# Function to calculate mid frequency
 calculate_mid_freq() {
    local min_freq=$(cat $1/cpufreq/cpuinfo_min_freq)
    local max_freq=$(cat $1/cpufreq/cpuinfo_max_freq)
    echo $(( (min_freq + max_freq) / 2 ))
 }

# Check if RAM is below the threshold
  if [[ "$TOTAL_RAM" -le "$LOW_RAM_THRESHOLD" ]]; then
    # Enable low RAM mode
    resetprop ro.config.low_ram true
    echo "Low RAM mode enabled (ro.config.low_ram set to true)."
  else
    echo "Device has more than 2GB RAM, no changes made."
  fi
  
# Loop over each CPU in the system
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
	# Fetch the available governors from the CPU
	avail_govs="$(cat "$cpu/scaling_available_governors")"

	# Attempt to set the governor in this order
	for governor in schedutil interactive powersave performance; do
	  # Once a matching governor is found, set it and break for this CPU
      if [[ "$avail_govs" == *"$governor"* ]]; then
        write "$cpu/scaling_governor" "$governor"
		break
      fi
	done
  done
  
# CPU Governor settings for LITTLE cores (cpu0-3)
  for cpu in /sys/devices/system/cpu/cpu[0-3]; do
    min_freq=$(cat $cpu/cpufreq/cpuinfo_min_freq)
    max_freq=$(cat $cpu/cpufreq/cpuinfo_max_freq)
    mid_freq=$(calculate_mid_freq $cpu)
     
     write $cpu/cpufreq/schedutil/hispeed_load "75"
     write $cpu/cpufreq/schedutil/iowait_boost_enable "0"
     write $cpu/cpufreq/schedutil/up_rate_limit_us "300"
     write $cpu/cpufreq/schedutil/down_rate_limit_us "2500"
     write $cpu/cpufreq/scaling_min_freq "$mid_freq"
     write $cpu/cpufreq/scaling_max_freq "$max_freq"
  done
  
# CPU Governor settings for big cores (cpu4-7)
  for cpu in /sys/devices/system/cpu/cpu[4-7]; do
    min_freq=$(cat $cpu/cpufreq/cpuinfo_min_freq)
    max_freq=$(cat $cpu/cpufreq/cpuinfo_max_freq)
    mid_freq=$(calculate_mid_freq $cpu)
  
     write $cpu/cpufreq/scaling_min_freq "$mid_freq"
     write $cpu/cpufreq/scaling_max_freq "$max_freq"
  done
    
# Schedule this ratio of tasks in the guarenteed sched period
  write /proc/sys/kernel/sched_min_granularity_ns "$((SCHED_PERIOD / SCHED_TASKS))"

# Require preeptive tasks to surpass half of a sched period in vmruntime
  write /proc/sys/kernel/sched_wakeup_granularity_ns "$((SCHED_PERIOD / 3))"
  
# Reduce the maximum scheduling period for lower latency
  write /proc/sys/kernel/sched_latency_ns "$SCHED_PERIOD"

# Reduce task migration frequency (ns)
  write /proc/sys/kernel/sched_migration_cost_ns "200000"

# Period for real-time duty cycle (us)
  write /proc/sys/kernel/sched_rt_period_us "2000000"

# Latency of the scheduler to assign task turns (ns)
  write /proc/sys/kernel/sched_latency_ns "5000000"

# Minimum granularity for light duty (ns)
  write /proc/sys/kernel/sched_min_granularity_ns "100000"

# Reduce system load during profiling
  write /proc/sys/kernel/perf_event_max_sample_rate "100000"

# Maximum stack frames that perf can collect during profiling
  write /proc/sys/kernel/perf_event_max_stack "64"

# Balancing real-time responsiveness and CPU availability (us)
  write /proc/sys/kernel/sched_rt_runtime_us "1800000"

# Upper and lower limits for CPU utility settings
  write /proc/sys/kernel/sched_util_clamp_max "768"
  write /proc/sys/kernel/sched_util_clamp_min "28"

# Reduce scheduler migration time to improve real-time latency
  write /proc/sys/kernel/sched_nr_migrate "16"

# Limiting complexity and overhead when profiling
  write /proc/sys/kernel/perf_event_max_contexts_per_stack "4"

# Perf event processing timeout (in percentage of CPU)
  write /proc/sys/kernel/perf_cpu_time_max_percent "5"

# Initial settings for the next parameter values
  write /proc/sys/kernel/sched_tunable_scaling "1"
  
# Execute child process before parent after fork
  write /proc/sys/kernel/sched_child_runs_first "1"
  
# can improve the isolation of CPU-intensive processes.
  write /proc/sys/kernel/sched_autogroup_enabled "0"

# Disable scheduler statistics to reduce overhead
  write /proc/sys/kernel/sched_schedstats "0"
    
# Always allow sched boosting on top-app tasks
  write /proc/sys/kernel/sched_min_task_util_for_colocation "0"

# Disable compatibility logging.
  write /proc/sys/kernel/compat-log "0"
    
# improves security by preventing users from triggering malicious commands or debugging.
  write /proc/sys/kernel/sysrq "0"
 
# background daemon writes pending data to disk.
  write /proc/sys/vm/dirty_writeback_centisecs "200"
    
# before data that is considered "dirty" must be written to disk.
  write /proc/sys/vm/dirty_expire_centisecs "500"
  
# Controlling kernel tendency to use swap
  write /proc/sys/vm/swappiness "60"
   
# Determines the percentage of physical RAM that can be allocated to additional virtual memory during overcommit.
  write /proc/sys/vm/overcommit_ratio "50"
   
# Specifies the interval (in seconds) for updating kernel virtual memory statistics.
  write /proc/sys/vm/stat_interval "30"
  
# Clearing the dentry and inode cache.
  write /proc/sys/vm/vfs_cache_pressure "75"

# The maximum percentage of system memory that can be used for "dirty" data before being forced to write to disk.
  write /proc/sys/vm/dirty_ratio "15"
    
# The percentage of memory that triggers "dirty" data writing to disk in the background.
  write /proc/sys/vm/dirty_background_ratio "5"
    
# Determines the number of memory pages loaded at once when reading from swap.
  write /proc/sys/vm/page-cluster "0"
    
# Specifies the increase in memory reserve on the watermark to avoid running out of memory.
  write /proc/sys/vm/watermark_boost_factor "0"
    
# Controls logging of disk I/O activity.
  write /proc/sys/vm/block_dump "0"
    
# Determines whether the kernel prioritizes killing tasks that allocate memory when an OOM (Out of Memory) occurs.
  write /proc/sys/vm/oom_kill_allocating_task "0"
    
# Controls whether the kernel records running task information when an OOM occurs.
  write /proc/sys/vm/oom_dump_tasks "0"
  
# Disable TCP timestamps for reduced overhead
  write /proc/sys/net/ipv4/tcp_timestamps "0"

# Enable TCP low latency mode
  write /proc/sys/net/ipv4/tcp_low_latency "1"

# Set up for I/O
 for queue in /sys/block/*/queue; do
	# Choose the first governor available
	avail_scheds="$(cat "$queue/scheduler")"
	for sched in cfq mq-deadline deadline none; do
		if [[ "$avail_scheds" == *"$sched"* ]]; then
			write "$queue/scheduler" "$sched"
			break
		fi
	done

	# Do not use I/O as a source of randomness
	 write $queue/add_random "0"

	# Disable I/O statistics accounting
	 write $queue/iostats "0"

	# Reduce the maximum number of I/O requests in exchange for latency
	 write $queue/nr_requests "64"
	
	# Determines the quantum of time (in milliseconds) given to a task in one CPU scheduler cycle. 
	 write $queue/quantum  "32"
	
	# Controls the merging of I/O requests.
     write $queue/nomerges "2"
    
    # Controls how I/O queues relate to the CPU.
     write $queue/rq_affinity "1"
    
    # Controls whether the scheduler provides additional idle time for I/O.
     write $queue/iosched/slice_idle "0"
    
    # Disable additional idle for groups.
     write $queue/group_idle "0"
    
    # Controls whether entropy from disk operations is added to the kernel randomization pool.
     write $queue/add_random "0"
    
    # Identifying the device as non-rotational.
     write $queue/rotational "0"
 done
    
# Enable Dynamic Fsync
  write /sys/kernel/dyn_fsync/Dyn_fsync_active "1"
  
# Printk (thx to KNTD-reborn)
  write /proc/sys/kernel/printk "0 0 0 0"
  write /proc/sys/kernel/printk_devkmsg "off"
  write /sys/kernel/printk_mode/printk_mode "0"
  
# Enable power efficiency
  if [ -d "/sys/module/workqueue/" ]; then
    write /sys/module/workqueue/parameters/power_efficient "1"
  fi
   
# Change kernel mode to HMP Mode
  if [ -d "/sys/devices/system/cpu/eas/" ]; then
    write /sys/devices/system/cpu/eas/enable "0"
  fi
	
# additional settings in kernel
  if [ -d "/sys/kernel/ged/hal/" ]; then
    write /sys/kernel/ged/hal/gpu_boost_level "2"
  fi

  if [ -d "/sys/kernel/debug/" ]; then
  # Consider scheduling tasks that are eager to run
	write /sys/kernel/debug/sched_features "NEXT_BUDDY"

  # Schedule tasks on their origin CPU if possible
	write /sys/kernel/debug/sched_features "TTWU_QUEUE"
  fi
  
# Kernel Panic Off & additional settings
  sysctl -w kernel.panic=0
  sysctl -w vm.panic_on_oom=0
  sysctl -w kernel.panic_on_oops=0
  sysctl -w kernel.sched_util_clamp_min_rt_default=0
  sysctl -w kernel.sched_util_clamp_min=128
     
# cleaning
  write /proc/sys/vm/drop_caches "3"
     
# Always return success, even if the last write fails
  end && sync && exit 0

# This script will be executed in late_start service mode
