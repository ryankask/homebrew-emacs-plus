;;; apple-emoji-ink-metrics.el --- GUI probe for the custom font patch -*- lexical-binding: t; -*-

;; Run a separate macOS GUI Emacs, not --batch:
;; /path/to/Emacs -Q -l tests/apple-emoji-ink-metrics.el
;; Exits nonzero on failure.  Results go to EMOJI_TEST_LOG or
;; /tmp/emacs-plus-emoji-tests.el.  An unpatched or ink-metrics-only build
;; should fail the fractional-size tests.

(require 'ert)
(require 'cl-lib)
(require 'face-remap)

(unless (and (eq system-type 'darwin) (display-graphic-p))
  (error "This probe requires a macOS GUI Emacs; do not use --batch"))

(defun emacs-plus-emoji-test-font (family size &rest properties)
  "Open FAMILY at pixel SIZE with extra font-spec PROPERTIES."
  (let* ((spec (apply #'font-spec :family family properties))
         (entity (find-font spec)))
    (should entity)
    (let ((font (open-font entity size)))
      (should font)
      (should (eq (font-get font :type) 'mac-ct))
      font)))

(defun emacs-plus-emoji-test-metrics (font)
  "Return SIZE, HEIGHT, ASCENT, and DESCENT for FONT."
  (let ((info (font-info font)))
    (mapcar (lambda (index) (aref info index)) '(2 3 8 9))))

(ert-deftest apple-emoji-ink-metrics-opt-in ()
  (let ((normal (emacs-plus-emoji-test-font "Apple Color Emoji" 12))
        (compact (emacs-plus-emoji-test-font
                  "Apple Color Emoji" 12 :use-ink-metrics t)))
    ;; Same glyph size; only the line-layout metrics change.
    (should (equal (emacs-plus-emoji-test-metrics normal) '(12 20 15 5)))
    (should (equal (emacs-plus-emoji-test-metrics compact) '(12 17 13 4)))))

(ert-deftest apple-emoji-ink-metrics-other-fonts-unchanged ()
  (let ((normal (emacs-plus-emoji-test-font "Iosevka" 14))
        (opted-in (emacs-plus-emoji-test-font "Iosevka" 14 :use-ink-metrics t)))
    (should (equal (emacs-plus-emoji-test-metrics normal)
                   (emacs-plus-emoji-test-metrics opted-in)))))

(ert-deftest apple-emoji-ink-metrics-cache-isolation ()
  (let* ((normal (emacs-plus-emoji-test-font "Apple Color Emoji" 12))
         (before (emacs-plus-emoji-test-metrics normal))
         (compact (emacs-plus-emoji-test-font
                   "Apple Color Emoji" 12 :use-ink-metrics t))
         (normal-again (emacs-plus-emoji-test-font "Apple Color Emoji" 12))
         (disabled (emacs-plus-emoji-test-font
                    "Apple Color Emoji" 12 :use-ink-metrics nil)))
    (should-not (eq normal compact))
    (should (equal before (emacs-plus-emoji-test-metrics normal)))
    (should (equal before (emacs-plus-emoji-test-metrics normal-again)))
    (should (equal before (emacs-plus-emoji-test-metrics disabled)))
    (should (< (nth 1 (emacs-plus-emoji-test-metrics compact))
               (nth 1 before)))))

(ert-deftest apple-emoji-ink-metrics-fractional-size ()
  (let ((compact (emacs-plus-emoji-test-font
                  "Apple Color Emoji" 14 :use-ink-metrics t))
        (fractional (emacs-plus-emoji-test-font
                     "Apple Color Emoji" 14 :use-ink-metrics t
                     :ink-metrics-scale 0.978)))
    ;; Preserve the nominal Emacs size while fitting the CoreText artwork.
    (should (equal (emacs-plus-emoji-test-metrics compact) '(14 19 15 4)))
    (should (equal (emacs-plus-emoji-test-metrics fractional) '(14 18 14 4)))))

(defconst emacs-plus-emoji-test-text
  "look what\nhappens\n😂❤️✨💯👍\nto the line height\nmixed text 😂❤️✨💯👍 end\n👩‍💻 👨‍👩‍👧‍👦 🧑🏽‍🚀 👍🏻 👍🏿\n🇬🇧 🇺🇸 🇯🇵\n1️⃣ 2️⃣ #️⃣ *️⃣\n☀️ ⚠️ ☕️ ©️ ™️\n")

(defun emacs-plus-emoji-test-lines (&optional face zoom fractional-scale first-visible)
  "Measure sample lines with FACE, ZOOM, and optional FRACTIONAL-SCALE.
Without FRACTIONAL-SCALE, use the original 0.9 fontset scaling.
With FIRST-VISIBLE, measure each line at the top of the window."
  (set-face-attribute 'default nil :family "Iosevka" :height 140)
  (let ((face-font-rescale-alist
         (unless fractional-scale '(("Apple Color Emoji" . 0.9))))
        (spec (font-spec :family "Apple Color Emoji" :use-ink-metrics t)))
    (when fractional-scale
      (font-put spec :ink-metrics-scale fractional-scale))
    (set-fontset-font t 'emoji spec)
    (with-current-buffer (generate-new-buffer " *emoji ink metrics*")
      (unwind-protect
          (progn
            (switch-to-buffer (current-buffer))
            (fundamental-mode)
            (setq-local line-spacing nil)
            (display-line-numbers-mode 1)
            (insert emacs-plus-emoji-test-text)
            (when face
              ;; Keep the first two lines plain to catch mixed-face height changes.
              (save-excursion
                (goto-char (point-min))
                (forward-line 2)
                (put-text-property (point) (point-max) 'face face)))
            (when zoom (text-scale-set zoom))
            (goto-char (point-min))
            (let (heights)
              (dotimes (_ (count-lines (point-min) (point-max)))
                (when first-visible
                  (set-window-start (selected-window) (point) t))
                (redisplay t)
                (push (line-pixel-height) heights)
                (forward-line))
              (nreverse heights)))
        (kill-buffer (current-buffer))))))

(ert-deftest apple-emoji-ink-metrics-line-heights ()
  (should (equal (emacs-plus-emoji-test-lines) (make-list 9 18))))

(ert-deftest apple-emoji-ink-metrics-mixed-faces ()
  (dolist (face '(bold italic))
    (should (equal (emacs-plus-emoji-test-lines face) (make-list 9 18)))))

(ert-deftest apple-emoji-ink-metrics-text-scaling ()
  (dolist (zoom '(-1 1 2))
    (let ((heights (emacs-plus-emoji-test-lines nil zoom)))
      (should-not (= (car heights) 18))
      (should (apply #'= heights)))))

(ert-deftest apple-emoji-ink-metrics-fractional-cache-isolation ()
  (let* ((normal (emacs-plus-emoji-test-font "Apple Color Emoji" 14))
         (compact (emacs-plus-emoji-test-font
                   "Apple Color Emoji" 14 :use-ink-metrics t))
         (fractional (emacs-plus-emoji-test-font
                      "Apple Color Emoji" 14 :use-ink-metrics t
                      :ink-metrics-scale 0.978))
         (normal-again (emacs-plus-emoji-test-font "Apple Color Emoji" 14))
         (compact-again (emacs-plus-emoji-test-font
                         "Apple Color Emoji" 14 :use-ink-metrics t)))
    (should-not (eq compact fractional))
    (should (equal (emacs-plus-emoji-test-metrics fractional) '(14 18 14 4)))
    (should (equal (emacs-plus-emoji-test-metrics normal) '(14 23 18 5)))
    (should (equal (emacs-plus-emoji-test-metrics normal-again) '(14 23 18 5)))
    (should (equal (emacs-plus-emoji-test-metrics compact-again) '(14 19 15 4)))))

(ert-deftest apple-emoji-ink-metrics-fractional-scope ()
  ;; The scale alone must not opt in, and must never affect other fonts.
  (dolist (family '("Apple Color Emoji" "Iosevka"))
    (let ((normal (emacs-plus-emoji-test-font family 14))
          (scale-only (emacs-plus-emoji-test-font
                       family 14 :ink-metrics-scale 0.978)))
      (should (equal (emacs-plus-emoji-test-metrics normal)
                     (emacs-plus-emoji-test-metrics scale-only)))))
  (let ((normal (emacs-plus-emoji-test-font "Iosevka" 14))
        (opted-in (emacs-plus-emoji-test-font
                   "Iosevka" 14 :use-ink-metrics t :ink-metrics-scale 0.978)))
    (should (equal (emacs-plus-emoji-test-metrics normal)
                   (emacs-plus-emoji-test-metrics opted-in)))))

(ert-deftest apple-emoji-ink-metrics-fractional-invalid-scales ()
  (let ((compact (emacs-plus-emoji-test-font
                  "Apple Color Emoji" 14 :use-ink-metrics t)))
    (dolist (scale '(nil bogus 0 1 0.0 1.0 -0.5 2.0))
      (let ((invalid (emacs-plus-emoji-test-font
                      "Apple Color Emoji" 14 :use-ink-metrics t
                      :ink-metrics-scale scale)))
        (should (equal (emacs-plus-emoji-test-metrics compact)
                       (emacs-plus-emoji-test-metrics invalid)))))))

(ert-deftest apple-emoji-ink-metrics-fractional-line-heights ()
  (should (equal (emacs-plus-emoji-test-lines nil nil 0.978) (make-list 9 18))))

(ert-deftest apple-emoji-ink-metrics-fractional-first-visible-row ()
  (should (equal (emacs-plus-emoji-test-lines nil nil 0.978 t) (make-list 9 18))))

(ert-deftest apple-emoji-ink-metrics-fractional-mixed-faces ()
  (dolist (face '(bold italic))
    (should (equal (emacs-plus-emoji-test-lines face nil 0.978) (make-list 9 18)))))

(ert-deftest apple-emoji-ink-metrics-fractional-screen-metrics ()
  ;; Integer-only legacy screen metrics must not disagree with the artwork.
  (let ((font (emacs-plus-emoji-test-font
               "Apple Color Emoji" 14 :use-ink-metrics t
               :ink-metrics-scale 0.978 :destination 1)))
    (should (equal (emacs-plus-emoji-test-metrics font) '(14 18 14 4)))))

(ert-deftest apple-emoji-ink-metrics-fractional-nominal-sizes ()
  ;; The factor follows the requested size, rather than fixing it at 13.692.
  (let ((smaller (emacs-plus-emoji-test-font
                  "Apple Color Emoji" 11 :use-ink-metrics t
                  :ink-metrics-scale 0.978))
        (larger (emacs-plus-emoji-test-font
                 "Apple Color Emoji" 20 :use-ink-metrics t
                 :ink-metrics-scale 0.978)))
    (should (= (car (emacs-plus-emoji-test-metrics smaller)) 11))
    (should (= (car (emacs-plus-emoji-test-metrics larger)) 20))
    (should (< (nth 1 (emacs-plus-emoji-test-metrics smaller))
               (nth 1 (emacs-plus-emoji-test-metrics larger))))))

;; Let startup finish before inspecting the GUI glyph matrix.
(run-at-time
 0.3 nil
 (lambda ()
   (condition-case err
       (let* ((stats (ert-run-tests-batch "^apple-emoji-ink-metrics-"))
              (failed (ert-stats-completed-unexpected stats))
              (log (or (getenv "EMOJI_TEST_LOG") "/tmp/emacs-plus-emoji-tests.el")))
         (with-temp-file log
           (prin1
            (list :tests (ert-stats-total stats) :unexpected failed
                  :results
                  (mapcar
                   (lambda (test)
                     (let ((result (ert-test-most-recent-result test)))
                       (list (ert-test-name test)
                             :passed (ert-test-passed-p result)
                             :condition
                             (when (ert-test-result-with-condition-p result)
                               (ert-test-result-with-condition-condition result)))))
                   (ert-select-tests "^apple-emoji-ink-metrics-" t)))
            (current-buffer)))
         (kill-emacs (if (zerop failed) 0 1)))
     (error
      (message "Emoji GUI probe failed: %S" err)
      (kill-emacs 1)))))
