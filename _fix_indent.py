import io
p = "D:/BoomCraft/MineRoulette/scripts/main.gd"
s = open(p, encoding="utf-8").read()
lines = s.split("\n")
# Fix the two unindented lines in the rocks loop (must begin with a single tab)
targets = ('rm.emission = Color("#6a1a0e")', 'rm.emission_energy_multiplier = 0.6')
fixed = 0
for i, ln in enumerate(lines):
    for t in targets:
        if ln.lstrip("\t ").startswith(t) and not ln.startswith("\t"):
            lines[i] = "\t" + ln.lstrip("\t ")
            fixed += 1
            break
open(p, "w", encoding="utf-8").write("\n".join(lines))
print("fixed lines:", fixed)
