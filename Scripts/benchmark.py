"""Measure Montclair and newly spawned WebKit processes during a controlled run."""
import json
import subprocess
import sys
import time

def snapshot():
    raw = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss=,pcpu=,comm="], text=True)
    result = {}
    for line in raw.splitlines():
        parts = line.strip().split(None, 4)
        if len(parts) == 5:
            result[int(parts[0])] = dict(ppid=int(parts[1]), rss_kib=int(parts[2]), cpu=float(parts[3]), command=parts[4])
    return result

baseline = snapshot()
process = subprocess.Popen([sys.argv[1], "--benchmark"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
measurements = []
for line in process.stdout:
    print(line.strip(), flush=True)
    if not line.startswith("BENCH ") or "done" in line:
        continue
    samples = []
    for _ in range(3):
        table = snapshot()
        selected = {pid: row for pid, row in table.items()
                    if pid == process.pid or (pid not in baseline and "WebKit" in row["command"])}
        samples.append(dict(total_rss_mib=round(sum(r["rss_kib"] for r in selected.values()) / 1024, 2),
                            app_rss_mib=round(table.get(process.pid, {}).get("rss_kib", 0) / 1024, 2),
                            cpu_percent=sum(r["cpu"] for r in selected.values()),
                            processes=selected))
        time.sleep(0.7)
    measurements.append(dict(phase=line.strip(), samples=samples))
    print(json.dumps(measurements[-1]), flush=True)
code = process.wait(timeout=20)
result = dict(exit_code=code, methodology="RSS sum of app plus WebKit PIDs absent before launch; other apps spawning WebKit can affect totals. ps CPU is an OS recent estimate, not battery usage.", measurements=measurements)
with open(sys.argv[2], "w") as file:
    json.dump(result, file, indent=2)
