# Blind labelling of non-exact rule outputs (test set)

Each file in `items/` shows, for one held-out driver file, the **human fix** and one **rule output**, both as diffs
against the original file. The rule's source (frontier LLM, Spinfer, or one of the local models) is hidden. Do **not**
open `key.csv` until every row of `labels.csv` has a label.

For each item, fill the `label` column of `labels.csv` with one of:

| label | meaning |
|---|---|
| `correct_equivalent` | the rule output performs the same migration as the human, with the same behaviour; only form differs (formatting, order of independent edits, an equivalent expression) |
| `correct_alternative` | a valid, behaviour-preserving migration that differs from the human's choice (e.g. converts a site the human converted in a later commit, or a different but correct API variant) |
| `partial` | the edits it makes are correct, but it leaves part of the migration undone in this file |
| `wrong` | it makes at least one edit that changes behaviour incorrectly, or would not compile in any configuration |
| `no_migration` | it changes nothing that belongs to the migration |

Use `note` for a one-line reason, especially for `wrong` and `correct_alternative`. When unsure between two labels,
choose the less favourable one and say why in `note`. Then run `python3 scripts/merge_labels.py`.
