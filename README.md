# knayawp.el

Germán's opinionated wrapper on magit + vterm + claude.el. Might evolve into a layout manager. Who knows.

## Installation

### Requirements

- **Emacs 29.1+**
- **[magit](https://magit.vc/)** (3.0 or newer)
- A terminal backend — **[vterm](https://github.com/akermu/emacs-libvterm)** (the default) or **[eat](https://codeberg.org/akib/emacs-eat)**. Select it with `knayawp-terminal-backend` (`'vterm` by default, or `'eat`).

knayawp targets Emacs 29+ throughout. The install paths below are listed in priority order.

### Primary — `package-vc` (Emacs 29+ built-in)

`package-vc` is built into Emacs 29.1, gives you the full end-user experience (generated autoloads, byte-compilation, package-registry integration), and can track GitHub HEAD directly.

```elisp
;; End user — install from GitHub HEAD:
(package-vc-install "https://github.com/germanD/knayawp.el")

;; Contributor / dogfooder — install from a local checkout
;; through real package machinery:
(package-vc-install-from-checkout "/path/to/knayawp.el" "knayawp")
```

### Secondary — `use-package :vc`

On **Emacs 30+** the `:vc` keyword is native:

```elisp
(use-package knayawp
  :vc (:url "https://github.com/germanD/knayawp.el" :rev :newest))
```

On **Emacs 29** `:vc` needs the [`vc-use-package`](https://github.com/slotThe/vc-use-package) shim. It is not on ELPA/MELPA, so install it with `package-vc` and then require it:

```elisp
(package-vc-install "https://github.com/slotThe/vc-use-package")
(require 'vc-use-package)

(use-package knayawp
  :vc (:fetcher github :repo "germanD/knayawp.el"))
```

On Emacs 29 the primary `package-vc-install` path above avoids this third-party shim entirely and is the simpler choice.

### From source / manual

For hacking on the package, add the checkout to your `load-path` and require it. This skips autoload generation and byte-compilation (do those by hand), so it is not recommended for end users:

```elisp
(add-to-list 'load-path "/path/to/knayawp.el/")
(require 'knayawp)
```

### MELPA

Not yet available. MELPA is the intended long-term distribution channel but still needs a recipe submission and review; `package-vc` is the bridge until then.

### Suggested keybinding

knayawp never binds `C-c LETTER` keys for you (those are reserved for users). Bind the command map yourself:

```elisp
(global-set-key (kbd "C-c k") knayawp-command-map)
```

Then `C-c k l` runs `knayawp-layout-setup` to build the project layout, and `C-c k q` tears it down.

For running multiple isolated project instances, see the dogfooding launcher under `test/`.
