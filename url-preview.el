;;; url-preview.el --- Preview urls in buffer.

;; This file is not part of Emacs

;; Copyright (C) 2014 Andreu Gil Pàmies
;; Filename: url-preview.el
;; Version: 0.1
;; Keywords: url
;; Author: Andreu Gil Pàmies <agpchil@gmail.com>
;; Created: 28-11-2014
;; Description: preview urls in buffer.
;; URL: http://github.com/agpchil/url-preview.el
;; Package-Requires: ((dash "2.9.0") (emacs "24"))
;; Compatibility: Emacs24

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:
(require 'dash)
(require 'url-queue)

(defgroup url-preview nil
  "Url preview."
  :link '(url-link :tag "Github" "https://github.com/agpchil/url-preview.el")
  :group 'url)

(defcustom url-preview-modules nil
  "List of url preview modules.
Each element is a plist that represents a module.

Module definition:

  :name               module name string
  :pattern            url pattern string
  :retrieve           function to retrieve url content
  :retrieve-url       function to modify url
  :retrieve-args      function to add extra args
  :retrieve-error     callback for `url-queue-retrieve'
  :retrieve-success   callback for `url-queue-retrieve'
  :on-success         list of functions to call seq
  :on-error           list of functions to call seq
  :enabled            nil or t
  :buffer             nil or buffer name
  :display-at         function to get display position mark
  :display            display function"
  :group 'url-preview
  :type '(list (repeat plist)))

(defface url-preview-prefix-string-face
  '((t :inherit font-lock-type-face))
  "Face for prefix string."
  :group 'url-preview)

(defcustom url-preview-prefix-string "url-preview"
  "Prefix string of url-preview message."
  :group 'url-preview)

(defcustom url-preview-cache-path (expand-file-name "url-preview" temporary-file-directory)
  "Path where to store download content."
  :group 'url-preview)

(defcustom url-preview-display-hook nil
  "Hook to call after preview is displayed (still inside `with-current-buffer')."
  :type 'hook
  :group 'url-preview)

(defun url-preview-module-define (module)
  "Add MODULE to `url-preview-modules' if not already defined."
  (let* ((name (plist-get module :name))
         (old-module (url-preview-module-find-by-name name)))
    (unless old-module
      (add-to-list 'url-preview-modules module))))

(defun url-preview-module-find-by-name (name)
  "Find first module with NAME."
  (--first (equal (plist-get it :name) name)
           url-preview-modules))

(defun url-preview-module-enabled-list ()
  "Return all enabled modules."
  (--filter (plist-get it :enabled)
            url-preview-modules))

(defun url-preview-module-enable (name)
  "Enable the module by NAME."
  (--when-let (url-preview-module-find-by-name name)
    (plist-put it :enabled t)))

(defun url-preview-module-disable (name)
  "Disable the module by NAME."
  (--when-let (url-preview-module-find-by-name name)
    (plist-put it :enabled nil)))

(defun url-preview-display (module msg-or-func marker)
  "Display MODULE by inserting or calling MSG-OR-FUNC before MARKER."
  (let* ((module-buffer (plist-get module :buffer))
         (buffer (or module-buffer (marker-buffer marker))))
    (with-current-buffer (get-buffer-create buffer)
      (save-excursion
        (let ((inhibit-read-only t))
          (cond (module-buffer
                 (goto-char (point-max)))
                (t
                 (goto-char (marker-position marker))))
          (let ((pt-before (point)))
            (cond ((functionp msg-or-func)
                   (funcall msg-or-func))
                  (t
                   (insert-before-markers msg-or-func)))
            (put-text-property pt-before (point) 'read-only t)
            (run-hooks 'url-preview-display-hook)))))))

(defun url-preview-display-at-nextline ()
  "Return (point-marker) for next line."
  (forward-line 1)
  (point-marker))

(defun url-preview-display-at-point ()
  "Return (point-marker)."
  (point-marker))

(defun url-preview-format (frm &rest args)
  "Create [url-preview]-prefixed string based on format FRM and ARGS."
  (concat
   "[" (propertize url-preview-prefix-string
                   'face
                   'url-preview-prefix-string-face) "] "
   (apply 'format frm args)))

(defun url-preview-cb-message (module msg)
  "Default callback to format the MODULE MSG."
  (url-preview-format "%s - %s\n"
                      (plist-get module :name)
                      msg))

(defun url-preview-cb-error-message (module error-info)
  "Default callback to format the MODULE ERROR-INFO."
  (let ((error-name (car error-info))
        (error-msg (cadr error-info)))
    (url-preview-format "%s (%s): %s\n"
                        (plist-get module :name)
                        error-name
                        error-msg)))

(defun url-preview-cb-save-cache (module)
  "Default callback to save the MODULE data cache."
  (let* ((url (plist-get module :url))
         (cache-file (url-preview-cache-file-name url)))
    (unless (file-exists-p cache-file)
      (unless (file-exists-p url-preview-cache-path)
        (make-directory url-preview-cache-path))
      (write-region (point) (point-max) cache-file))
    nil))

(defun url-preview-cb-save-cache-binary (module)
  "Default callback to save the MODULE data cache as binary."
  (let ((coding-system-for-write 'binary))
    (url-preview-cb-save-cache module)
    nil))

(defun url-preview-delete-cache ()
  "Delete the cache path (with confirmation prompt)."
  (interactive)
  (let* ((msg (format "Delete cache directory from disk (%s)?" url-preview-cache-path))
         (really-delete-p (yes-or-no-p msg)))
    (when really-delete-p
      (delete-directory url-preview-cache-path t)
      (message (format "Deleted directory %s" url-preview-cache-path)))))


(defun url-preview-funcall-list (func-list module &optional initial)
  "Call each function in FUNC-LIST.
Pass the MODULE and the return value of previous one as argument.
INITIAL value will be passed at the first function call if available.
Return the last function result."
  (let ((result initial))
    (-each func-list
      (lambda(func)
        (setq result (cond (result
                            (funcall func module result))
                           (t (funcall func module))))))
    result))

(defun url-preview-retrieve-success (module marker)
  "Default callback for `url-queue-retrieve' success.
It calls the `:on-success' list of functions and
finally call the display function from MODULE.
The module is displayed at MARKER position."
  (let* ((on-success-func (plist-get module :on-success))
         (on-success-func-list (if (listp on-success-func)
                                   on-success-func
                                 (list on-success-func)))
         (display-func (or (plist-get module :display)
                           'url-preview-display))
         (msg (url-preview-funcall-list on-success-func-list
                                        module)))
    (when msg
      (funcall display-func module msg marker))))

(defun url-preview-retrieve-error (error-info module marker)
  "Default callback for `url-queue-retrieve' error.
It calls the `:on-error' list of functions with ERROR-INFO
and finally call the display function from MODULE.
The module is displayed at MARKER position."
  (let* ((on-error-func (plist-get module :on-error))
         (on-error-func-list (if (listp on-error-func)
                                 on-error-func
                               (list on-error-func)))
         (display-func (or (plist-get module :display)
                           'url-preview-display))
         (msg (url-preview-funcall-list on-error-func-list
                                        module
                                        error-info)))
    (when msg
      (funcall display-func module msg marker))))

(defun url-preview-retrieve-callback (status module marker)
  "Callback function for `url-queue-retrieve'.
Use the STATUS to detect if `url-queue-retrieve' success
or error.  And then call the proper function with MODULE
and MARKER arguments."
  (let ((error-info (plist-get status :error))
        (error-callback (or (plist-get module :retrieve-error)
                            'url-preview-retrieve-error))
        (success-callback (or (plist-get module :retrieve-success)
                              'url-preview-retrieve-success)))
    (cond (error-info
           (funcall error-callback (cdr error-info) module marker))
          (t (funcall success-callback module marker)))))

(defun url-preview-cache-file-name (url)
  "Return the file name used for cache for URL.
This doesn't create the file."
  (expand-file-name (md5 url) url-preview-cache-path))

(defun url-preview-cache-file (url)
  "Return the file used for cache for URL or nil if not exist."
  (let ((file (url-preview-cache-file-name url)))
    (if (file-exists-p file)
        file
      nil)))

(defun url-preview-retrieve-queue-or-cache (module url callback &optional cbargs silent inhibit-cookies)
  "Call the queue or cache MODULE retrieve function for URL with CALLBACK.
CBARGS SILENT and INHIBIT-COOKIES will be passed to `url-queue-retrieve'
if available."
  (let* ((url (plist-get module :url))
         (cache-file (url-preview-cache-file url)))
    (cond (cache-file
           (with-temp-buffer
             (erase-buffer)
             (insert-file-contents cache-file)
             (apply callback nil cbargs)))
          (t
           (url-queue-retrieve url
                               callback
                               cbargs
                               silent)))))

(defun url-preview-retrieve (module url marker)
  "Default retrieve function for MODULE using URL at MARKER."
  (let* ((retrieve-url-func (or (plist-get module :retrieve-url)
                              'identity))
         (url-mod (funcall retrieve-url-func url))
         (args nil))

    (when url-mod
      (plist-put module :url url-mod)

      (when (plist-get module :retrieve-args)
        (funcall (plist-get module :retrieve-args) module))

      (setq args (list module marker))
      (url-preview-retrieve-queue-or-cache module
                                           url-mod
                                           'url-preview-retrieve-callback
                                           args
                                           t))))

(defun url-preview-module-call (module url marker)
  "Use MODULE to preview the URL at MARKER."
  (let ((display-at-func (or (plist-get module :display-at)
                             'url-preview-display-at-nextline))
        (retrieve-func (or (plist-get module :retrieve)
                           'url-preview-retrieve))
        (display-at-marker nil)
        (module-copy (copy-tree module)))

    (goto-char marker)
    (setq display-at-marker (funcall display-at-func))

    (funcall retrieve-func module-copy url display-at-marker)))

(defun url-preview-module-call-maybe (module url marker)
  "Call MODULE with the proper function to process an URL at MARKER."
  (let ((re (plist-get module :pattern)))
    (when (string-match-p re url)
      (url-preview-module-call module url marker))))

(defun url-preview (beg end)
  "Preview url at point, region or line.
Interactive set BEG and END."
  (interactive (cond ((use-region-p)
                      (list (region-beginning) (region-end)))
                     ((thing-at-point 'url)
                      (let ((bounds (bounds-of-thing-at-point 'url)))
                        (list (car bounds) (cdr bounds))))
                     (t
                      (list nil nil))))

  (save-excursion
    (url-preview-handler beg end)))

(defun url-preview-search-urls (beg end)
  "Search urls between BEG and END positions.
Return a list of markers"
  (let* ((line (buffer-substring-no-properties beg end))
         (regexp "http")
         (index (string-match regexp line 0))
         (markers-list nil))
    (while index
      (goto-char beg)
      (setq index (1+ index))
      (forward-char index)
      (when (thing-at-point 'url)
        (goto-char (end-of-thing 'url))
        (add-to-list 'markers-list (point-marker)))
      (setq index (string-match regexp line index)))
    markers-list))

(defun url-preview-handler (&optional beg end)
  "Call the proper module to preview the urls.
BEG and END limits the search range.
By default it uses (point-at-bol)
 and (point-at-eol) instead."
  (if beg
      (goto-char beg)
    (beginning-of-line))

  (let* ((beg (or beg (point-at-bol)))
         (end (or end (point-at-eol)))
         (url-markers (url-preview-search-urls beg end))
         (modules (url-preview-module-enabled-list))
         (url nil))

    (-each url-markers
      (lambda(mark)
        (goto-char mark)
        (setq url (thing-at-point 'url))

        (-each modules
          (lambda(module)
            (url-preview-module-call-maybe module url (point-marker))))))
    t))

(provide 'url-preview)
;;; url-preview.el ends here
