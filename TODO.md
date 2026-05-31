# Possible enhancements

Ideas not yet implemented. Each notes the motivation and the rough approach /
known difficulty.

## Reflow soft-wrapped paragraphs (CommonMark / README semantics)

markdown-modern renders the buffer text as-is, so a hard-wrapped paragraph
(one written across several physical lines) keeps its line breaks. This differs
from how the *same* file renders as a GitHub README, where a single newline
inside a paragraph is a soft break collapsed to a space, so the paragraph
reflows into one flowing block. (GitHub only preserves single newlines in
issues/PRs/comments, not in rendered `.md` files.)

Enhancement: an option to visually collapse intra-paragraph single newlines to a
space, so hard-wrapped sources render like a GitHub README.

- Approach: in the paragraph renderer, put a `display " "` overlay over each
  intra-paragraph newline (and any leading indentation of the continuation
  line), so successive source lines flow together; `visual-line-mode` then
  wraps the joined text at the window edge.
- Difficulty: medium. Watch out for: not collapsing the *last* newline (block
  boundary), interaction with the reveal-at-point logic (the newline overlay is
  display-bearing, so reveal would expose it — which is probably fine), code
  blocks / tables / lists must be excluded, and point motion across the
  collapsed newline.
- Make it a defcustom (default nil to keep current behavior; or default t for
  README-faithful rendering — decide based on the reading-first use case).

## Keep tables rendered while editing

When point enters a table, reveal-at-point currently un-renders the whole table
to raw pipe source so it can be edited. That is jarring for a wide/long table:
the rendered box vanishes and reappears.

Enhancement: keep the box-rendered table visible while editing, revealing only
the minimum needed.

- Options, simplest to richest:
  1. **Row-level reveal**: keep every table row rendered except the row under
     point, which shows its raw `| a | b |` source. Re-render that row on leave.
     Reuses the existing per-row table overlays (`table-create-overlays` already
     builds one overlay per source line), so this is mostly a matter of teaching
     the reveal path to operate at row granularity for tables instead of
     whole-block.
  2. **Cell-level reveal**: reveal only the current cell's text.
  3. **org-style table editor**: TAB/`S-TAB` between cells, auto-realign on
     edit, never show raw pipes — the nicest but the most work (essentially a
     mini reimplementation of `org-table`).
- Difficulty: (1) low–medium and high value; (3) high.
- Note the related existing affordance: `markdown-modern-edit-code-block`
  (`C-c '`) opens a code block in a dedicated buffer; a similar
  "edit-table-in-a-grid" command could be an alternative to inline cell editing.

## Further marker / element reveals not yet covered

The line-leading markers (list bullets, ordered markers, task checkboxes,
blockquote markers) are now revealed at point. Still not revealed:

- **Display math** (`$...$`, `$$...$$`) — not in the reveal types, so the
  rendered Unicode/SVG math can't be edited by putting point on it.
- Anything else rendered via a `display` glyph that is not a parse marker.

---

Done:

- Code-block syntax highlighting wired up (1.0.1).
- Reveal line-leading markers (bullets, ordered, checkboxes, blockquote) and
  heading `#` markers at the heading's size (Unreleased — see CHANGELOG).
