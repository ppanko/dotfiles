;;; p3-config-gptel.el --- GPTel configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar gptel-api-key)
(defvar gptel-model)

(declare-function gptel-api-key-from-auth-source "gptel" ())
(declare-function p3/gptel-setup "p3-gptel" ())

(use-package gptel
  :config
  (setq gptel-model 'gpt-4o-mini
        gptel-api-key (or (getenv "OPENAI_API_KEY")
                          #'gptel-api-key-from-auth-source)))

;; Preserve the existing `:after gptel' activation boundary while making the
;; dedicated behavior library participate in exact-source config reloads.
(with-eval-after-load 'gptel
  (p3/config-load-module 'p3-gptel)
  (p3/gptel-setup))

(provide 'p3-config-gptel)

;;; p3-config-gptel.el ends here
