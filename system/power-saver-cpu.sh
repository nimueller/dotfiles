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

apply() {
    local profile policy max limit pick f
    profile=$(busctl --system get-property "$dest" "$path" "$dest" ActiveProfile 2>/dev/null) || return
    profile=${profile#s \"}
    profile=${profile%\"}
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        max=$(<"$policy/cpuinfo_max_freq")
        pick=$max
        if [[ $profile == power-saver ]]; then
            # The highest available frequency within the limit
            limit=$((max * 70 / 100))
            pick=$(<"$policy/cpuinfo_min_freq")
            for f in $(<"$policy/scaling_available_frequencies"); do
                ((f <= limit && f > pick)) && pick=$f
            done
        fi
        echo "$pick" >"$policy/scaling_max_freq"
    done
    echo "$profile: $(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq | tr '\n' ' ')"
}

apply
gdbus monitor --system --dest "$dest" --object-path "$path" | while read -r line; do
    [[ $line == *ActiveProfile* ]] && apply
done
