#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
# thanks to tytydraco & notzeetaa & all developer for reference this module kernel

# ----------------- VARIABLES -----------------
   SCHED_PERIOD="$((4 * 1000 * 1000))"
   SCHED_TASKS="8"
   UINT_MAX="4294967295"
   KERNEL_PATH="/proc/sys/kernel"
   KERNEL2_PATH="/sys/kernel"
   KERNEL_DEBUG_PATH="/sys/kernel/debug"
   MODULE_KERNEL_PATH="/sys/module/kernel"
   CPU_EAS_PATH="/sys/devices/system/cpu/eas"
   VM_PATH="/proc/sys/vm"
   NET_PATH="/proc/sys/net"

# Detect if we are running on Android
grep -q android /proc/cmdline && ANDROID=true

# ----------------- HELPER FUNCTIONS -----------------
log() {
    echo "$1"
}

write_value() {
    local file="$1"
    local value="$2"
    if [ -e "$file" ]; then
        chmod +w "$file" 2>/dev/null
        echo "$value" > "$file" && log "Write : $file → $value" || log "Failed to Write : $file"
    fi
}

# Function to calculate mid frequency
calculate_mid_freq() {
    local min_freq=$(cat $1/cpufreq/cpuinfo_min_freq)
    local max_freq=$(cat $1/cpufreq/cpuinfo_max_freq)
    echo $(( (min_freq + max_freq) / 2 ))
}

wait_until_boot_completed && sync
# ----------------- OPTIMIZATION CPU SECTIONS -----------------
# Loop over each CPU in the system (@tytydraco (ghitub))
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
	# Fetch the available governors from the CPU
	avail_govs="$(cat "$cpu/scaling_available_governors")"

	# Attempt to set the governor in this order
	for governor in schedutil schedplus ondemand userspace interactive powersave performance; do
	  # Once a matching governor is found, set it and break for this CPU
      if [[ "$avail_govs" == *"$governor"* ]]; then
        write_value "$cpu/scaling_governor" "$governor"
		break
      fi
	done
  done
  
# Apply governor specific tunables for interactive (@tytydraco (ghitub))
find /sys/devices/system/cpu/ -name interactive -type d | while IFS= read -r governor
do
	# Consider changing frequencies once per scheduling period
	write_value "$governor/timer_rate" "$((SCHED_PERIOD / 1000))"
	write_value "$governor/min_sample_time" "$((SCHED_PERIOD / 1000))"

	# Jump to hispeed frequency at this load percentage
	write_value "$governor/go_hispeed_load" "90"
	write_value "$governor/hispeed_freq" "$UINT_MAX"
done

# CPU Governor settings for big cores (cpu4-7) (thx to @Bias_khaliq)
for cpu in /sys/devices/system/cpu/cpu[4-7]; do
    min_freq=$(cat $cpu/cpufreq/cpuinfo_min_freq)
    max_freq=$(cat $cpu/cpufreq/cpuinfo_max_freq)
    mid_freq=$(calculate_mid_freq $cpu)
 
        write_value "$cpu/cpufreq/scaling_min_freq" "$mid_freq"
        write_value "$cpu/cpufreq/scaling_max_freq" "$max_freq"
done

# CPU Governor settings for LITTLE cores (cpu0-3) (thx to @Bias_khaliq)
for cpu in /sys/devices/system/cpu/cpu[0-3]; do
    min_freq=$(cat $cpu/cpufreq/cpuinfo_min_freq)
    max_freq=$(cat $cpu/cpufreq/cpuinfo_max_freq)
    mid_freq=$(calculate_mid_freq $cpu)
 
        write_value "$cpu/cpufreq/scaling_min_freq" "$mid_freq"
        write_value "$cpu/cpufreq/scaling_max_freq" "$max_freq"
done

# -------- OPTIMIZATION KERNEL SECTIONS --------

# Schedule this ratio of tasks in the guarenteed sched period
  write_value "$KERNEL_PATH/sched_min_granularity_ns" "$((SCHED_PERIOD / SCHED_TASKS))"

# Require preeptive tasks to surpass half of a sched period in vmruntime
  write_value "$KERNEL_PATH/sched_wakeup_granularity_ns" "$((SCHED_PERIOD / 2))"
  
# Reduce the maximum scheduling period for lower latency
  write_value "$KERNEL_PATH/sched_latency_ns" "$SCHED_PERIOD"

# Real-time time period
  write_value "$KERNEL_PATH/sched_rt_period_us" "1000000"

# Reduce task migration frequency (ns)
  write_value "$KERNEL_PATH/sched_migration_cost_ns" "500000"

# Period for real-time duty cycle (us)
  write_value "$KERNEL_PATH/sched_rt_period_us" "2000000"

# Latency of the scheduler to assign task turns (ns)
  write_value "$KERNEL_PATH/sched_latency_ns" "6000000"

# Minimum granularity for light duty (ns)
  write_value "$KERNEL_PATH/sched_min_granularity_ns" "750000"

# Reduce system load during profiling
  write_value "$KERNEL_PATH/perf_event_max_sample_rate" "50000"
  
# Specifies the time window size (in nanoseconds) for CPU time sharing calculations.
  write_value "$KERNEL_PATH/sched_shares_window_ns" "5000000"
  
# sets the average duration (time averaging period) in milliseconds for task load tracking calculation by the scheduler.
  write_value "$KERNEL_PATH/sched_time_avg_ms" "700"
  
# gives an initial value of the task load based on a specified percentage
  write_value "$KERNEL_PATH/sched_walt_init_task_load_pct" "20"

# Maximum stack frames that perf can collect during profiling
  write_value "$KERNEL_PATH/perf_event_max_stack" "32"
  
# prevent excessive memory consumption by perf events
  write_value "$KERNEL_PATH/perf_event_mlock_kb" "570"

# Balancing real-time responsiveness and CPU availability (us)
  write_value "$KERNEL_PATH/sched_rt_runtime_us" "950000"

# Upper and lower limits for CPU utility settings
  write_value "$KERNEL_PATH/sched_util_clamp_max" "768"
  write_value "$KERNEL_PATH/sched_util_clamp_min" "128"

# determines the CPU utilization level that triggers task migration to another CPU during high load.
  write_value "$KERNEL_PATH/sched_upmigrate" "95 85"
  write_value "$KERNEL_PATH/sched_downmigrate" "95 60"

# Reduce scheduler migration time to improve real-time latency
  write_value "$KERNEL_PATH/sched_nr_migrate" "32"

# Limiting complexity and overhead when profiling
  write_value "$KERNEL_PATH/perf_event_max_contexts_per_stack" "4"

# Limit max perf event processing time to this much CPU usage
  write_value "$KERNEL_PATH/perf_cpu_time_max_percent" "5"

# Scheduler boosting allows temporary priority increases for certain threads or processes to gain more CPU time.
  write_value "$KERNEL_PATH/sched_boost" "1"
  
# Enable WALT for CPU utilization
  write_value "$KERNEL_PATH/sched_use_walt_cpu_util" "0"

# Enable WALT for task utilization
  write_value "$KERNEL_PATH/sched_use_walt_task_util" "0"
  
# Initial settings for the next parameter values
  write_value "$KERNEL_PATH/sched_tunable_scaling" "0"
  
# Execute child process before parent after fork
  write_value "$KERNEL_PATH/sched_child_runs_first" "0"

# Disables timer migration from one CPU to another.
  write_value "$KERNEL_PATH/timer_migration" "0"
  
# Disable CFS boost
  write_value "$KERNEL_PATH/sched_cfs_boost" "0"

# Disable isolation hint
  write_value "$KERNEL_PATH/sched_isolation_hint" "0"
  
# Disable Sched Sync Hint
  write_value "$KERNEL_PATH/sched_sync_hint_enable" "0"
  
# can improve the isolation of CPU-intensive processes.
  write_value "$KERNEL_PATH/sched_autogroup_enabled" "0"

# Disable scheduler statistics to reduce overhead
  write_value "$KERNEL_PATH/sched_schedstats" "0"
    
# Always allow sched boosting on top-app tasks
[[ "$ANDROID" == true ]] && write_value "$KERNEL_PATH/sched_min_task_util_for_colocation" "0"

# Disable compatibility logging.
  write_value "$KERNEL_PATH/compat-log" "0"
    
# improves security by preventing users from triggering malicious commands or debugging.
  write_value "$KERNEL_PATH/sysrq" "0"
 
# -------- OPTIMIZATION VM & QUEUE SECTIONS --------

# background daemon writes pending data to disk.
  write_value "$VM_PATH/dirty_writeback_centisecs" "500"
    
# before data that is considered "dirty" must be written to disk.
  write_value "$VM_PATH/dirty_expire_centisecs" "100"
  
# Controlling kernel tendency to use swap
  write_value "$VM_PATH/swappiness" "100"
   
# Determines the percentage of physical RAM that can be allocated to additional virtual memory during overcommit.
  write_value "$VM_PATH/overcommit_ratio" "50"
   
# Specifies the interval (in seconds) for updating kernel virtual memory statistics.
  write_value "$VM_PATH/stat_interval" "30"
  
# Clearing the dentry and inode cache.
  write_value "$VM_PATH/vfs_cache_pressure" "100"

# The maximum percentage of system memory that can be used for "dirty" data before being forced to write_value" "to disk.
  write_value "$VM_PATH/dirty_ratio" "30"
    
# The percentage of memory that triggers "dirty" data writing to disk in the background.
  write_value "$VM_PATH/dirty_background_ratio" "10"
    
# Determines the number of memory pages loaded at once when reading from swap.
  write_value "$VM_PATH/page-cluster" "0"
    
# Specifies the increase in memory reserve on the watermark to avoid running out of memory.
  write_value "$VM_PATH/watermark_boost_factor" "0"
    
# Controls logging of disk I/O activity.
  write_value "$VM_PATH/block_dump" "0"
    
# Determines whether the kernel prioritizes killing tasks that allocate memory when an OOM (Out of Memory) occurs.
  write_value "$VM_PATH/oom_kill_allocating_task" "0"
    
# Controls whether the kernel records running task information when an OOM occurs.
  write_value "$VM_PATH/oom_dump_tasks" "0"
  
# Set up for I/O thx to (@tytydraco (ghitub))
 for queue in /sys/block/*/queue; do
	# Choose the first governor available
	avail_scheds="$(cat "$queue/scheduler")"
	for sched in mq-deadline deadline none; do
		if [[ "$avail_scheds" == *"$sched"* ]]; then
			write_value "$queue/scheduler" "$sched"
			break
		fi
	done

	# Do not use I/O as a source of randomness
	 write_value "$queue/add_random" "0"

	# Disable I/O statistics accounting
	 write_value "$queue/iostats" "0"

	# Reduce the maximum number of I/O requests in exchange for latency
	 write_value "$queue/nr_requests" "64"
	
	# Determines the quantum of time (in milliseconds) given to a task in one CPU scheduler cycle. 
	 write_value "$queue/quantum " "32"
	
	# Controls the merging of I/O requests.
     write_value "$queue/nomerges" "2"
    
    # Controls how I/O queues relate to the CPU.
     write_value "$queue/rq_affinity" "1"
    
    # Controls whether the scheduler provides additional idle time for I/O.
     write_value "$queue/iosched/slice_idle" "0"
    
    # Disable additional idle for groups.
     write_value "$queue/group_idle" "0"
    
    # Controls whether entropy from disk operations is added to the kernel randomization pool.
     write_value "$queue/add_random" "0"
    
    # Identifying the device as non-rotational.
     write_value "$queue/rotational" "0"
 done
  
# -------- OPTIMIZATION NET SECTIONS --------

# Disable TCP timestamps for reduced overhead
  write_value "$NET_PATH/ipv4/tcp_timestamps" "0"

# Enable TCP low latency mode
  write_value "$NET_PATH/ipv4/tcp_low_latency" "1"

# -------- OPTIMIZATION OTHER SETTINGS SECTIONS --------

# Enable Dynamic Fsync
  write_value "$KERNEL2_PATH/dyn_fsync/Dyn_fsync_active" "1"
  
# Disabled Kernel Tracing
  write_value "$KERNEL2_PATH/tracing/tracing_on" "0"
  
# Printk (thx to KNTD-reborn)
  write_value "$KERNEL_PATH/printk" "0 0 0 0"
  write_value "$KERNEL_PATH/printk_devkmsg" "off"
  write_value "$KERNEL2_PATH/printk_mode/printk_mode" "0"
  
# Disable Kernel Panic
  for KERNEL_PANIC in $(find /proc/sys/ /sys/ -name '*panic*'); do
    write_value "$KERNEL_PANIC" "0"
  done
   
# Change kernel mode to HMP Mode
  if [ -d "$CPU_EAS_PATH/" ]; then
    write_value "$CPU_EAS_PATH/enable" "0"
  fi
	
# additional settings in kernel
  if [ -d "$KERNEL2_PATH/ged/hal/" ]; then
    write_value "$KERNEL2_PATH/ged/hal/gpu_boost_level" "2"
  fi

  if [ -d "$KERNEL_DEBUG_PATH/" ]; then
  # Consider scheduling tasks that are eager to run
	write_value "$KERNEL_DEBUG_PATH/sched_features" "NEXT_BUDDY"

  # Schedule tasks on their origin CPU if possible
	write_value "$KERNEL_DEBUG_PATH/sched_features" "TTWU_QUEUE"
  fi
  
# additional settings
  sysctl -w kernel.sched_util_clamp_min_rt_default=0
     
# cleaning
  write_value "$VM_PATH/drop_caches" "3"
  write_value "$VM_PATH/compact_memory" "1"
     
# Always return success, even if the last write fails
  sync

# This script will be executed in late_start service mode
