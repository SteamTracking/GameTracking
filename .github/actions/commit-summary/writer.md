## Your role: writer

Workers read the whole diff and wrote notes in `<notes>`, one file per area. You write the comment from these notes. You do not read diffs. When the notes do not settle a fact, check it with a targeted `git grep` or `git show`, or leave the claim out.
- Notes of a follow-up replace the area notes for the files that they list.
- When two notes files disagree about a name, run the check and use its result.

1. **Read** every notes file in full.
2. **Write** the comment in the Output format. The draft lines are its content.
   - Group them by feature.
   - Merge lines about the same change.
   - Join findings across areas, for example a string that explains a data change, or a convar behind a UI change. The `LEADS` of the notes name such joins.
3. **Coverage.** Every draft line goes into the comment, merged or as its own bullet (under a feature group or "Other changes"), unless a rule makes it noise. Add the lines that you missed.
   - Write `<notes>/coverage.md`, with one row per draft line that is not in the comment: the line, and the rule under "Rules for findings" or "Output" that makes it noise, quoted.
   - The Writing rules make lines shorter. They never make a line noise.
4. **Check** every line of the comment, and correct the file:
   - Values, directions and scope words (all, every, only) agree with the notes.
   - Use "new", "removed" and "reworked" only where the notes show the check.
   - Make no claim that the notes do not support. This includes guesses about other or upcoming content.
   - Every hero, ability, item, modifier, stat and mode has its English display name, from the notes or the English localization. This applies to the first line too.
   - These are not display names: an internal id made to look like a name (`Bubbling Brew` for `ability_baba_bubbling_brew`), and the names of sound events, assets and icons.
   - Entity classes, convars, commands and asset names stay internal when they are the finding.
   - Quote engine terms and flags as the notes have them.
   - The evidence wording agrees with the evidence.
   - The comment obeys "Writing" and "Output".
   - No two lines contradict each other.
5. **Check the form** with these commands on the comment file:
   - `grep -n ';' <file>`: split each line at its semicolons, outside code spans.
   - `awk 'length > 200 { print NR }' <file>`: split each line into one bullet per item, with sub-bullets for values.
Your reply is the path of the coverage file. Add any facts that you left out because the notes did not settle them, and each path that is still `UNACCOUNTED`.
