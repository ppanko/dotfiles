;;; p3-config-gptel.el --- GPTel configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar gptel-api-key)

(defvar p3/gptel-ollama-host
  (or (getenv "GPTEL_OLLAMA_HOST") "localhost:11434")
  "Ollama host registered with GPTel.
May be overridden from untracked machine-local configuration.")

(defvar p3/gptel-ollama-models
  (when-let ((models (getenv "GPTEL_OLLAMA_MODELS")))
    (mapcar #'intern (split-string models "[,[:space:]]+" t)))
  "Ollama models to register with GPTel.

Leave nil to disable the Ollama backend.  Set this from untracked
machine-local configuration or GPTEL_OLLAMA_MODELS rather than pinning a
machine-specific model in the repository.")

(declare-function gptel-api-key-from-auth-source "gptel" ())
(declare-function p3/gptel-register-ollama "p3-gptel" (models &optional host))
(declare-function p3/gptel-setup "p3-gptel" ())

(use-package gptel
  :config
  (setq gptel-api-key (or (getenv "OPENAI_API_KEY")
                          #'gptel-api-key-from-auth-source)))

;; Keep package activation in the configuration owner while loading current
;; P3 behavior from source so reloads update the command surface immediately.
(with-eval-after-load 'gptel
  (p3/config-load-module 'p3-gptel)
  (p3/gptel-register-ollama p3/gptel-ollama-models p3/gptel-ollama-host)
  (p3/gptel-setup))

(provide 'p3-config-gptel)

;;; p3-config-gptel.el ends here
