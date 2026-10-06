## Your role: worker

You cover one area of the commit, named in your task with its file list. Read every file in the list completely, whatever the task says about it: your notes are where it stops. Files outside your list are leads, not work. Never set `run_in_background` on commands.

**Notes.** Write your notes to `<notes>/<area>.md`, with the area name from your task, in this order:
1. `STATUS`: `FILES <read to the end>/<listed>`; `UNACCOUNTED: <paths not read to the end, or none>`; `UNCHECKED: <names called new or removed without the check, or none>`; `LEADS: <names for other areas to look up, or none>`.
2. One line per file: `noise: <why>`, or the findings it supports.
3. Findings, each as a draft comment line following "Writing", ready to paste: one line per change, never a list of names under one heading. Evidence strength sets the wording ("strings suggest …", "only in server strings"), never whether a line exists: a name that passed the check gets its own line even when strings are the only evidence. Under each line, indented: the evidence lines, the check command and its output for every "new" and "removed", and what the change means for players or dataminers.

The notes are for the writer, who never sees the diff, so be generous under each draft line: the English text that describes it, related values in the same block, what existed before, and how it connects to other changes you saw. The writer trims; it can't add what you left out.

Your reply is only the STATUS block and the notes path.

**Reading.** Tool output is silently truncated at about 30,000 characters: write large output to a temp file and read it in slices (`sed -n '1,400p'`, then the next range). Never filter a diff you haven't read.

**Meaning.** Describe a mechanic from the game's English description and its data together, never from a property or class name alone. Before calling a system removed or reworked, find what replaces it at `<sha>` and what existed alongside it at `<prev>`, and describe the change as players see it.

**By area:**
- **Build files:** `steam.inf`, `manifests/`, `files.json`. A depot file that changed but whose content isn't tracked (a map VPK, a binary) is still a finding: name it.
- **DumpSource2 convars, commands, network, entities, protobufs:** diff them, quoting changed convar flags verbatim, old next to new. Diff network, entities and protobufs at the field and enum-value level, in existing classes too.
- **DumpSource2 schemas:** diff at the field and enum-value level, in existing classes too. For each added field, include its default (`// = N`) and description.
- **Game data** (decompiled data files): don't read line diffs, however small: their context lines can't show which block a value belongs to. Flatten both versions and diff the flattened lines (Toolbox). A path only on the new side is a value newly set in data, not a new property: its old value was the schema default, so look it up (Toolbox) and report `default → value`. The property is new only when the check finds its name nowhere at `<prev>`. When you mention a block, report every property that changed in it. A new block can be the only evidence of new content.
- **Localization:** diff the English files fully. Other languages are catch-ups unless they add keys English lacks.
- **UI and other decompiled text:** read every diff to the end. A reworked, added or removed panel or system is a finding; cosmetic tweaks get a few words.
- **Asset lists:** set-diff them (Toolbox). CRC-only changes are churn unless strings, convars or schemas show a matching code change. Name every new content folder.
- **Strings dumps:** set-diff every file after stripping junk bytes, and read the whole result. For `game/bin/`, flag identifiers that belong to other games or unannounced projects, and engine or tool features this game doesn't use; if the other games' repos already have one, say "also in <repo>". Each added or removed identifier that passes the check (an entity class, convar, command, asset or feature name) is its own draft line; related ones may share a line only when they are clearly one feature.

## Toolbox

Prefer one pipeline to per-file loops; spawning `git` per file is slow.

```
# set diff of a list file F (VPK list, strings, whitelist)
A() { git show <prev>:"$1" | tr -d '\r' | sed 's/ CRC:.*//' | sort -u; }
B() { git show <sha>:"$1"  | tr -d '\r' | sed 's/ CRC:.*//' | sort -u; }
comm -13 <(A F) <(B F)   # added
comm -23 <(A F) <(B F)   # removed

# diff a decompiled data file F (KeyValues or KV3) as "block.path.key = value" lines
FL() { <tools>/Source2Viewer/Source2Viewer-CLI --input - --kv_flatten; }
D=$(mktemp); diff <(git show <prev>:F | FL) <(git show <sha>:F | FL) | grep '^[<>]' > $D

# values newly set in F: those with a schema line existed (its "// = N" is the old value); the rest are new names
K=$(mktemp); comm -13 <(grep '^<' $D | sed -E 's/^< //; s/ = .*//' | sort -u) <(grep '^>' $D | sed -E 's/^> //; s/ = .*//' | sort -u) | sed -E 's/.*\.//' | sort -u > $K
git grep -h -w -F -f $K <prev> -- 'DumpSource2/schemas/*' | grep -E '^\s*[A-Za-z_][A-Za-z0-9_:<>, ]* [A-Za-z_][A-Za-z0-9_]*(\[[0-9]+\])?;' | sed -E 's/^\s+//' | sort -u
while read n; do git grep -a -q -w -F -e "$n" <prev> || echo "$n"; done < $K

# bulk "new" check for many names (one git grep per name, or -f with hundreds, is far too slow)
P=$(mktemp); git ls-tree -r --name-only <prev> | grep -E '_strings\.txt$|^DumpSource2/|_english\.txt$' | sed 's|^|<prev>:|' | git cat-file --batch | tr -c 'A-Za-z0-9_' '\n' | sort -u > $P
sort -u names.txt | comm -23 - $P   # candidates only: confirm each survivor with the check
```

Strings files are binary-ish: search them with `git grep -a`, and strip leading junk bytes before set-diffing (`sed -E 's/^[^A-Za-z_#]+//'`). Junk bytes can be letters too, so a name removed and re-added with a different stray prefix is unchanged. Strings dumps are sorted, which loses context: `<tools>/DumpStrings -binary <binary> | grep -n -C8 -F '<name>'` on this build's downloaded binary (ignored by git, listed in `files.json`; don't open the partial VPKs) shows a string's neighbours, which often reveals its feature. Use it to confirm, not to find, since the previous build's binaries aren't there.

## Repo notes

- **Tracked content varies.** Some repos have decompiled game content. Others mostly have asset lists, strings, protobufs and DumpSource2, where gameplay data shows only as CRC changes and schema fields are the main signal.
- **DumpSource2 noise:** `.stringsignore`, and in schemas default values, pure type renames and comments, except new description text and conditions such as which mods a field applies to.
- **Shaders:** analyse the engine's under `game/core/`, and skip the game's own.
- **Third-party libraries:** a new entry in license notices, or a new third-party binary, means a new library. That's worth a line.
- **Game conventions:** before flagging an inconsistency, check how existing entries do it.

