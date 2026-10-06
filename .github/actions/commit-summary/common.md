# GameTracking commit summary

Find everything that changed in a Valve Source 2 game between two builds, and report it to dataminers as a comment on the commit. The diff is the job; the comment is its report. A missed change or a wrong claim costs more than time.

GameTracking repos track a game's files under `game/` and the dumps made from them: VPK listings (`*_dir.txt`), decompiled content, binary string dumps (`*_strings.txt`), protobufs, DumpSource2 (convars, commands, schemas, network, entities) and depot manifests (`manifests/`).

The repo is read-only. The working tree is at `<sha>`; read older builds with `git show <prev>:<path>`. Temp files from `mktemp` are expected.

## Rules for findings

- **Report changes to the game, not to the files.** Re-dumps, decompiler or serialiser changes, recompiles, lists catching up, strings moving between dumps and translation catch-ups are noise.
- **"New"** means the check finds nothing at `<prev>`; otherwise "newly listed in X". A path is new only if absent at `<prev>`, a folder only if nothing under it existed; otherwise "new files in X". A CRC change is not new content. A schema field that existed at `<prev>` with a default is not new when data starts setting it: report `default → value`. **"Removed"** means absent from the whole tree at `<sha>`. Check both sides of renames, and each name on its own, not by association with a feature.
- **The check.** "New": `git grep -a -w -F -c -e '<name>' <prev> | head -3` prints nothing; anything else means it existed, so say where. Substring or case-insensitive greps don't count either way. "Removed": the same at `<sha>` prints nothing.
- **Diff by meaning.** Compare lists as sets, both ways: names vanishing from the whole tree are findings too. In sorted files an edited string is a removal plus a near-identical addition: report it as a rename, old next to new. Collapse repeated identical edits. Normalise formats before concluding something changed.
- **A schema default is not the game's value:** report what the data sets.
- **Don't interpret engine terms by their everyday meaning.** Quote them, old next to new.
- **Display names** come from the English localization (`git ls-tree -r --name-only <sha> | grep -i english`), never from memory.
- **Evidence strength**, strongest first: game data and localization; schemas, protobufs and convars; asset lists; binary strings. When strings are the only evidence, say "strings suggest".
- **Never call anything a leak, unreleased or upcoming.** State the evidence instead, e.g. "only in tool binaries" or "no entity dump in this game implements it".

## Writing

For a dataminer skimming a feed:
- One terse line per change. Name things, don't describe files: no sizes, CRCs, hashes, versions, dates or tallies. Game values are fine.
- Give each change what a dataminer needs: the name, old → new values, convar defaults and flags, key strings and the mechanics the data shows. Leave out implementation detail (internal UI and style names, layout values, audio settings, full paths, enum numbers, descriptions that repeat the line) unless it's the evidence.
- A changed file whose content isn't tracked (a map VPK, a binary) is still worth naming.
- Mark inferences. Write impersonally, never "I".

