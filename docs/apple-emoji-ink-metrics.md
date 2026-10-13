# Apple Color Emoji ink metrics and fractional sizing

Archived experiment on `experiment/apple-emoji-ink-metrics`; not merged into `main`. The user chose Noto Color Emoji for everyday use rather than maintaining the Apple-specific rendering changes. The patch and tests are retained for reference.

This custom patch is opt-in and limited to the `mac-ct` font driver and the exact family `Apple Color Emoji`. Both properties below are defined by the patch, not standard Emacs settings.

## Settings

```elisp
(set-fontset-font t 'emoji
                  (font-spec :family "Apple Color Emoji"
                             :use-ink-metrics t
                             :ink-metrics-scale 0.978))
```

Do not also apply the old `0.8` or `0.9` entry in `face-font-rescale-alist`. Remove that entry from your configuration and restart the patched Emacs so existing font objects are not reused.

- `:use-ink-metrics t` derives font ascent/descent from the union of every glyph's reported drawing bounds, rounded outwards. Without the property, normal metrics remain unchanged.
- `:ink-metrics-scale 0.978` keeps Emacs's nominal font size, but uses a fractional CoreText size before glyph advances, bounds, and shaping are calculated. It requires the ink-metrics opt-in and accepts a finite floating-point value strictly between zero and one. Missing, invalid, or identity values leave the size unchanged.
- Synthetic bold receives a small additional reduction to allow for the stroke padding already included in the backend's glyph bounds. Fractionally scaled fonts use CoreText metrics rather than the integer-only legacy screen-font path.
- Other font families are unchanged, even if supplied these properties.

At nominal size 14, factor `0.978` gives CoreText size 13.692. Native measurements of all 3,844 glyphs give outward-rounded ascent/descent of 14/4, matching the 18-pixel Iosevka 14 line box. With synthetic bold's padding included, the adjusted size is approximately 13.53 and also measures 14/4.

## Build the separate test installation

Quit any running `emacs-plus-local` instance first. The Makefile uninstalls the previous local test build before installing the next one.

```bash
cd /Users/ryan/Projects/homebrew-emacs-plus

HOMEBREW_EMACS_PLUS_BUILD_CONFIG=/dev/null \
HOMEBREW_NO_INSTALL_CLEANUP=1 \
make formula-32 -- \
  --build-from-source \
  --skip-link \
  --without-native-compilation-aot
```

The config override avoids reapplying `ns-win`, which is already in this fork's formula. `--skip-link` leaves the existing command symlinks alone; do not copy the test app over `/Applications/Emacs.app`. Native compiler support remains enabled, but full-tree AOT compilation is skipped.

## GUI probe

```bash
EMACS="$(brew --prefix)/opt/emacs-plus-local/Emacs.app/Contents/MacOS/Emacs"
"$EMACS" -Q -l tests/apple-emoji-ink-metrics.el
```

Do not use `--batch`. The probe exits nonzero on unexpected results and writes the test counts and individual results to `/tmp/emacs-plus-emoji-tests.el`, or the path in `EMOJI_TEST_LOG`.

There are 15 tests. The original six cover ink-only behaviour with fontset scale `0.9`; the additions cover fractional metrics, font-cache isolation, family/opt-in restrictions, invalid factors, sample line heights, the first visible row, mixed faces, nominal size changes, and legacy screen metrics. They do not perform a pixel-level clipping audit. Check cursor redraws, scrolling, and complex sequences visually.

## Cursor background at larger sizes

The user reported a short black block-cursor rectangle at a larger text size. A GUI geometry probe at `text-scale-set` level 7 reproduced nominal emoji size 50, emoji metrics 44/8 (height 52), and a row height of 62 logical pixels. `posn-at-point` reports the emoji's character rectangle as 49×52.

The filled cursor's clipping in `xdisp.c` uses the character's ascent/descent and the frame's baseline line height, rather than necessarily filling the whole enlarged row. Cocoa's cursor drawing in `nsterm.m` uses those shared routines. Tight ink metrics expose the difference when the emoji's reserved height is smaller than Iosevka's row height. The artwork fits, but the cursor background is shorter and vertically inset.

A direct fix would require changes outside `macfont.m`, so it was not attempted under the user's one-source-file constraint. A bar cursor can make the mismatch less conspicuous, but is not a geometry fix.

## Limits and validation status

The fixed factor is tuned for Iosevka 14. It is not an automatic fit to an arbitrary main font or every zoom level: native measurements predict a one-pixel mismatch at some other sizes, including 12 and 16. Changing the main font or size can require a different factor.

The first ink-only revision was built and passed its six GUI tests. On that old build, the expanded probe reported 15 tests with six expected failures in fractional metrics and line heights.

The user subsequently rebuilt the fractional revision. The expanded GUI probe now reports `(:tests 15 :unexpected 0)` and exits with status zero; all individual tests passed. Results are in `/tmp/emacs-plus-emoji-fractional-positive.el`. The user's screenshot shows larger emoji and consistent spacing without obvious clipping in the four-line sample. This confirms the target Iosevka 14 case, not uniform heights at every zoom level or a complete pixel-level rendering audit.
