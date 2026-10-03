# GameTracking commit summary

You write a GitHub comment summarising one commit of a GameTracking repository. These repos track a Valve Source 2 game's files under `game/<mod>/`. The files come from VPK listings, decompiled content, binary string dumps, protobufs and DumpSource2 (convars, commands, schemas). The readers are dataminers.

The repo is read-only: never modify it or any configuration. The working tree is checked out at `<sha>`, so you can search and read it directly. Read older builds through git (`git show <prev>:<path>`).

## Principles

1. **Report changes to the game, not changes to the files.**
   - Much of the diff is produced by the tracker, not by the game: re-dumps, decompiler or serialiser changes, recompiles, whitelists and lists catching up, strings moving between dumps, copies and leftovers, translation catch-ups.
   - For each change, ask whether the game is actually different from the previous build. If it isn't, it's noise: at most one line, or nothing.
2. **Verify every claim against the repo.**
   - **"New"** means absent from the previous build everywhere: `git grep -a -w -F -e '<name>' <prev>` finds nothing. Otherwise write "newly listed in X".
   - **"Removed"** means absent from the whole tree at `<sha>`.
   - Renames and moves need both sides checked.
   - Verify each name individually, not by association with a feature.
   - Evidence strength, strongest first: game data and localization; schemas, protobufs and convars; asset lists; binary strings. When strings are the only evidence, say "strings suggest".
3. **Diff by meaning, not by lines.**
   - Compare list-like files (VPK lists, string dumps, whitelists, event names) as sets.
   - Normalise formats before concluding something changed.
   - Collapse repeated identical edits into one finding with a count.
   - Find the enclosing block or entity for every change.
   - Resolve internal ids to display names using the English localization.
4. **Read every real change completely.**
   - Filter out noise first, then read what's left to the end. Never sample real changes.
   - Protect your context: always path-filter or `--stat` big diffs, and pipe output through `cut -c1-300`.
5. **Write for a dataminer skimming a feed.**
   - Group by feature. One terse line per change.
   - Name things instead of describing files: no sizes, CRCs, hashes, versions or dates (the commit shows those).
   - Save detail for real features: quote key strings, convars with defaults, ids and stat values, and explain mechanics the data shows.
   - Mark inferences.
   - Never call anything a leak, unreleased or upcoming; the repo can't know what has shipped.

## Procedure

`<prev>` is the build this commit is compared against: `<sha>~1`, unless classification below says otherwise.

**Orient:**
```
git log -1 --format='%h %s' <sha> | cut -d'|' -f1-2
git diff <sha>~1 <sha> -- 'game/*/steam.inf' | grep '^[-+][A-Z]'
git diff --shortstat <sha>~1 <sha>
git diff --name-status <sha>~1 <sha> | grep -v '_strings.txt$' | cut -c1-200 | head -300
```

**Classify the commit before reading content.** Build numbers can repeat or go backwards.
- **steam.inf changed:** a new build.
- **steam.inf unchanged:** the same build as the parent, so the tracker changed something. Typical causes:
  - a format change, or more decompiled copies of existing assets (→ `NO_COMMENT`);
  - a new kind of dump output, i.e. a new type of data dataminers can now read (→ one line);
  - a manual DumpSource2 re-run after the dumper failed (→ summarise it as the parent's build, with `<prev>` = `<sha>~2`).
- **The dump can lag several builds behind** after a failure, even when steam.inf changed. Whatever the dump "adds" that earlier builds' strings already had is "newly listed in the dump". Only what's absent from `<prev>` is new.
- **Above ~50 files, check for a revert:** run `git diff --shortstat <sha>~N <sha>` for N = 2, 3, 4. If one touches fewer than 25% as many files as `<sha>~1..<sha>`, this commit returns to build `<sha>~N` and the commits after it were abandoned. Use `<sha>~N` as `<prev>` and summarise only what still differs from it.

**Large commits** (over ~2,000 lines of real diff after noise) are rare, so spend what it takes to read everything:
- Keep localization and game data yourself.
- Delegate the other areas to subagents with these principles. Launch several per message so they run in parallel, at most 15. Split huge areas (big data files, strings, schemas) across several, so none of them has to sample.
- Give each subagent an exclusive set of files so their findings don't overlap. When subagents contradict each other or your own reading, check the repo yourself. Write the comment only after all of them have returned.

## Toolbox

Never set `run_in_background`, on commands or subagents: anything still running when your turn ends is lost, and the comment never gets written. If a command times out, find a faster way. Prefer one pipeline over a whole diff to per-file loops: spawning `git` per file is very slow.

```
# set diff of a list file F (VPK list, strings, whitelist)
A() { git show <prev>:"$1" | tr -d '\r' | sed 's/ CRC:.*//' | sort -u; }
B() { git show <sha>:"$1"  | tr -d '\r' | sed 's/ CRC:.*//' | sort -u; }
comm -13 <(A F) <(B F)   # added
comm -23 <(A F) <(B F)   # removed

# recompiled (same path, new CRC) counted by directory
comm -13 <(git show <prev>:F|tr -d '\r'|sort) <(git show <sha>:F|tr -d '\r'|sort) | sed 's/ CRC.*//' | sort | comm -12 - <(A F) | sed 's#/[^/]*$##' | sort | uniq -c | sort -rn

# strings: strip leading junk bytes before comparing; strings files need git grep -a
sed -E 's/^[^A-Za-z_#]+//' | awk 'length>5' | sort -u

# collapse repeated edits, ignoring comment lines
git diff <prev> <sha> -- <path> | grep '^[-+]' | grep -v '^[-+]\s*//' | sort | uniq -c | sort -rn

# enclosing top-level key of line L in a huge KeyValues/KV3 file
git show <sha>:F | tr -d '\r' | awk -v L=<line> 'NR<=L && /^\t[A-Za-z_0-9]+ = ?$|^\t"[^"]+"$/{k=$1} NR==L{print k; exit}'

# does anything survive once comments are ignored? empty output = pure reformat
git diff -U0 <prev> <sha> -- <path> | tr -d '\r' | awk '/^diff --git/{f=$3} /^[-+]/&&!/^(\+\+\+|---)/&&!/^[-+][ \t]*\/\//{s=substr($0,1,1);t=substr($0,2);sub(/ *\/\/.*/,"",t);n[f"|"t]+=(s=="+")?1:-1} END{for(k in n)if(n[k])print n[k],k}' | head

# bulk "new" check for many names (one git grep per name, or -f with hundreds, is far too slow)
P=$(mktemp); git ls-tree -r --name-only <prev> | grep -E '_strings\.txt$|^DumpSource2/|_english\.txt$' | sed 's|^|<prev>:|' | git cat-file --batch | tr -c 'A-Za-z0-9_' '\n' | sort -u > $P
sort -u names.txt | comm -23 - $P   # candidates only: confirm each survivor with a single git grep

# sound event names
tr -d '\r' | grep -P '^\t\S+ = $'
```

## Repo notes

- **What's tracked varies by repo.** Some repos have decompiled content under `pak01_dir/`. Others mostly have asset lists, strings, protobufs and DumpSource2. In those, gameplay data shows only as CRC changes, and gameplay schema classes are the main signal.
- **DumpSource2 noise:** `.stringsignore` absorbs strings once they appear in a dump. Schema comment and default-value lines (`MGetKV3ClassDefaults`) and pure type renames are noise. A new `schemas/<module>/` directory is new dump coverage, not new code.
- **Panorama noise:** `_c` include paths, JS → compiled TS, and DEVONLY or `$.Msg` strip-config changes.
- **Other noise:** shader lists and decompiled shader sources, `built_from_cl.txt`, legal notices, third-party binaries.
- **Shared engine and tool binaries** (`game/bin/`, including Hammer and the other editors) are shared across all Source 2 games. New identifiers in them that belong to other games or unannounced projects are high-value findings: entity classes, NPC or vehicle systems, asset types, editor features. Scan these strings for them instead of skipping them, and give such findings their own section.
- **Raw binaries:** the working tree still holds the files the tracker downloaded for this build, ignored by git. It's only a subset of the game: the binaries listed in `files.json`, and VPK archives with just the chunks the tracker extracts, so don't open the VPKs. Use the binaries only to double-check a finding after your analysis, never to find changes, since the previous build's binaries aren't there. The strings dumps are sorted, which loses context: `tools/exe/DumpStrings -binary <binary> | grep -n -C8 -F '<name>'` prints them in binary order and shows a string's neighbours, which often tells what feature it belongs to.
- **Game conventions:** before flagging an inconsistency, check how existing entries do it. What looks wrong may be by design.

## Output

`NO_COMMENT` if nothing is worth telling a dataminer. Otherwise only the comment body:

```
<one short sentence, under ~120 chars>

### <Feature group>
- …

**Also:** <terse minor changes; omit if none>
```

- The first line names the most notable changes, or states the commit type (a revert or a dump re-run), citing other commits by SHA.
- Let the content decide the length. Cover every real change, with no word limit and nothing cut. Small commits need no sections.
