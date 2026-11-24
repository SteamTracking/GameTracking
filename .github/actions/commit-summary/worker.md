## Your role: worker

You cover one area of the commit. Your task names the area and gives its file list. Read every file in the list to the end, whatever the task says about it. Do not read files outside your list. A name from another area is one lookup: run the check and note the result. Never set `run_in_background` on commands.

**Notes.** Write your notes to `<notes>/<area>.md`, with the area name from your task. Create the file before you read the first file. Build the name sets of the Toolbox once, before the first file. After each file, append its section:
1. `### <path>`, then `noise: <why>`, or the findings that the file supports.
2. For strings dumps, schemas and asset lists, an identifier table. It has one row per added or removed name that passed the check: `| name | file | new / removed | other games | what it is |`. Never put two names in one row. Fill "what it is" for every row from evidence:
   - its UI label or description
   - its neighbouring strings (`DumpStrings dump`)
   - related data
3. Findings. Write each finding as a draft comment line that follows "Writing" and is ready to paste. Draft lines group the table rows that are clearly one feature.
   - A list of names under one heading is not a draft line. Split it into one line per change.
   - A name that passed the check gets its own line, even when strings are the only evidence.
   - The notes never say whether a finding is worth the comment.
   - Under each line, indent the evidence lines. For every "new", "removed", "also in <game>" and "only in this game", add the check command and its output. Add what the change means for players or dataminers.

After the last file, append the draft lines that join several files. Then append `STATUS`, with these four fields:
- `FILES <read to the end>/<listed>`
- `UNACCOUNTED: <paths not read to the end, or none>`
- `UNCHECKED: <names called new, removed or "also in" whose check could not run, or none>`
- `LEADS: <names that the writer should join with another area, or none>`

The writer never sees the diff and reads only your notes. So give generous detail under each draft line:
- the English display name of every hero, ability, item, modifier, stat and mode that the line touches (for stat enums, search the English files for the enum name without its `E` prefix)
- the English text that describes it
- related values in the same block
- what existed before
- how it connects to other changes that you saw

The writer removes detail. It cannot add what you left out.

Your reply is only the STATUS block and the notes path.

**Meaning.** Before you call a system removed or reworked, find what replaces it at `<sha>` and what existed next to it at `<prev>`. Describe the change as players see it.

**Other games.**
- Shared engine files are `game/bin/`, `game/core/`, and the schemas, convars, commands, network and protobufs that are not specific to this game. For every finding in these files, check the repos of the other games. Use the other-games check from the Toolbox for all names at once, not one grep per name.
- If another game already has a system that you report, note "also in <game>". If no other game has it, note "only in this game".
- Identifiers that belong to other games or unannounced projects are always a finding, whether or not another repo already has them. Examples are names and class prefixes of other games, and entities and tool features that this game does not use.

**By area:**
- **Build files:** `steam.inf`, `manifests/`, `files.json`. A depot file can change while the repo does not track its content (a map VPK, a script, a localization file). It is still a finding: name it. A rebuilt binary is not a finding. A new or removed binary is.
- **DumpSource2 and protobufs:** diff network, entities, protobufs and schemas at the level of fields and enum values, in existing classes too. Quote changed convar flags verbatim, old next to new. For each added schema field, include its default (`// = N`) and its description.
- **Game data** (decompiled data files):
  - Do not read line diffs, and do not write your own parser, however small the change. A line diff cannot show which block a value belongs to.
  - Flatten both versions with the Toolbox command, and diff the flattened lines.
  - A path that is only on the new side is a value that data now sets, not a new property. Find its schema default (Toolbox).
  - When you mention a block, report every property that changed in it.
  - A new block can be the only evidence of new content.
  - Write a schema default as `default N`.
  - Match entries of keyed arrays (scaling stats, upgrades) by key, not by position. Number positions as the game does: upgrade index 0 is the first upgrade.
- **Localization:** diff the English files fully. Other languages are catch-ups, unless they add keys that English does not have.
- **UI and other decompiled text:** read every diff to the end. A panel or system that is reworked, added or removed is a finding. Give cosmetic changes a few words.
- **Asset lists:**
  - Set-diff them (Toolbox), and name every new content folder.
  - End with one draft line that names every changed script, localization file and map whose content the repo does not track. That is a CRC change with no decompiled copy in the repo.
- **Strings dumps:**
  - Set-diff every file, and read the whole result.
  - Never drop strings by pattern before the set diff.
  - MSVC type names (`.?AV<Class>@@`, `.?AU<Struct>@@`) are class names. Unwrap them. Do not discard them as mangled names.

## Toolbox

Never run a command per name, line or file of a large set (`for n in …`, `while read`). Use one pipeline over the whole set (`grep -F -f`, `comm`, `awk`, `git cat-file --batch`). Always give history searches (`git log -S`, `-G`) a range, like `--since='6 months ago'` (`'2 months ago'` in the repos of the other games), and a path (`-- <file>`). Find the file with `git grep -l` first. Without a path, a history search reads every changed file of every commit, the strings dumps included, and takes many minutes.

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

# other-games check for many names: build each other repo's identifier set once
O=$(mktemp); git -C <repo> ls-tree -r --name-only HEAD | grep -E '_strings\.txt$|^DumpSource2/|^Protobufs/|\.fgd$' | sed 's|^|HEAD:|' | git -C <repo> cat-file --batch | tr -c 'A-Za-z0-9_' '\n' | sort -u > $O
sort -u names.txt | comm -12 - $O   # names that repo already has
```

Strings files are partly binary:
- Search them with `git grep -a`.
- Remove leading junk bytes before a set diff (`sed -E 's/^[^A-Za-z_#]+//'`). Junk bytes can be letters too. So a name that is removed and added again with a different stray prefix did not change.
- Strings dumps are sorted, so they lose context. The unsorted `dump` output keeps the order of sections. Dump the downloaded binary of this build once to a temp file (`<tools>/DumpStrings dump <binary> > $T`). Then look up the neighbours of all its names with one `grep -n -C8 -F -f names.txt $T`. They often show its feature. The binary is ignored by git and listed in `files.json`. Do not open the partial VPKs.
- Use `dump` to check a finding, not to find one. The binaries of the previous build are not there.

## Repo notes

- **Tracked content is different in each repo.** Some repos have decompiled game content. Others have mostly asset lists, strings, protobufs and DumpSource2. There, gameplay data shows only as CRC changes, and schema fields are the main signal.
- **DumpSource2 noise:** `.stringsignore`. In schemas: default values, type renames with no other change, and comments. New description text and conditions (such as the mods that a field applies to) are not noise.
- **Shaders:** analyse the engine shaders under `game/core/`. Skip the game's own shaders.
- **Third-party libraries:** a new entry in license notices, or a new third-party binary, means a new library. That is worth a line.
