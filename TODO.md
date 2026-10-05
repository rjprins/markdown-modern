# Maintenance pass

- [x] Fix test runners. `make test`, `make test-verbose`, `make test-count`
  and the interactive runner must cover all eight test suites.
- [x] Add CI. Check Emacs 30.1 and 31.1 with both parser paths on pushes,
  pull requests and a monthly schedule.
- [x] Fix packaging and quality checks. Build a versioned, installable tarball
  and fail when compilation or package lint reports a problem.
- [x] Publish a release. Version and changelog updated. The tested package is
  available as [1.1.0](https://github.com/rjprins/markdown-modern/releases/tag/1.1.0).
- [x] Improve installation and visibility. Test fresh installs, document
  tree-sitter setup, refresh the screenshot and build the MELPA recipe.

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

## Auto-increment and auto-renumber numeric lists

`markdown-modern-insert-list-item` already increments the next ordered-list
item when continuing a list. It does not yet renumber the surrounding numeric
list after inserting, deleting, moving, promoting, or demoting list items.

Enhancement: add commands and/or automatic cleanup for ordered Markdown lists.

- Approach: detect the ordered list containing point, preserve the marker style
  (`1.` vs `1)`), and renumber sibling items from the list's starting number.
  Call this after list item insertion/reordering and expose a manual
  `renumber-list` command.
- Difficulty: medium. Watch out for nested ordered lists, mixed ordered and
  unordered children, task lists, blockquoted lists, and Markdown's permissive
  rule that rendered numbering need not match source numbering.

## Further marker / element reveals not yet covered

The line-leading markers (list bullets, ordered markers, blockquote markers)
are now revealed at point. Task checkboxes are deliberately *not* revealed —
they are interactive widgets (`SPC` toggles, `Backspace`/`Delete` removes).
Still not revealed:

- **Display math** (`$...$`, `$$...$$`) — not in the reveal types, so the
  rendered Unicode/SVG math can't be edited by putting point on it.
- Anything else rendered via a `display` glyph that is not a parse marker.

---

Done:

- Code-block syntax highlighting wired up (1.0.1).
- Reveal line-leading markers (bullets, ordered, blockquote) and heading `#`
  markers at the heading's size (1.1.0).
- Task checkboxes as interactive widgets: no reveal; `SPC` toggles,
  `Backspace`/`Delete` removes the checkbox (1.1.0).
- Keep tables rendered while editing — implemented as row-level reveal with the
  active row drawn as an editable, pixel-aligned grid row (valign-style), plus
  fit-to-window table sizing so tables never wrap (1.1.0).
  Possible follow-ups: cell-level (rather than row-level) reveal, rendering
  inline markup inside cells, and giving an over-long active cell a horizontal
  scroll affordance instead of letting that one row extend past the window.
