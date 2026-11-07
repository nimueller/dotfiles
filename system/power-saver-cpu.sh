#!/usr/bin/env bash
# Power saver for power-profiles-daemon without a CPU driver of its own
# (only the "placeholder" one, e.g. on Snapdragon laptops), where the
# profile changes nothing by itself: power saver caps every CPU cluster at
# about 70 % of its top frequency, where the cores are the least efficient;
# balanced and performance lift the cap. Runs as root
# (power-saver-cpu.service, from system/setup.sh) and follows the profile
# over D-Bus.
set -u

dest=org.freedesktop.UPower.PowerProfiles
path=/org/freedesktop/UPower/PowerProfiles
cpufreq=/sys/devices/system/cpu/cpufreq
cap_percent=70

active_profile() {
    local reply
    reply=$(busctl --system get-property "$dest" "$path" "$dest" ActiveProfile) || return 1
    reply=${reply#s \"}
    echo "${reply%\"}"
}

# The highest available frequency of a CPU cluster within the cap
capped_frequency() {
    local policy=$1 max limit pick frequency
    max=$(<"$policy/cpuinfo_max_freq")
    limit=$((max * cap_percent / 100))
    pick=$(<"$policy/cpuinfo_min_freq")
    for frequency in $(<"$policy/scaling_available_frequencies"); do
        if ((frequency <= limit && frequency > pick)); then
            pick=$frequency
        fi
    done
    echo "$pick"
}

apply() {
    local profile policy pick maxima
    profile=$(active_profile) || return 1
    for policy in "$cpufreq"/policy*; do
        if [[ $profile == power-saver ]]; then
            pick=$(capped_frequency "$policy")
        else
            pick=$(<"$policy/cpuinfo_max_freq")
        fi
        echo "$pick" >"$policy/scaling_max_freq"
    done
    maxima=$(cat "$cpufreq"/policy*/scaling_max_freq | tr '\n' ' ')
    echo "$profile: $maxima"
}

apply
gdbus monitor --system --dest "$dest" --object-path "$path" | while read -r line; do
    if [[ $line == *ActiveProfile* ]]; then
        apply
    fi
done
