---
name: Bug report
about: Something the plugin does wrong
labels: bug
---

**What happened, and what you expected instead**

**Which Omarchy and Quickshell**

```
omarchy --version
```

**Anything the shell logged**

Quickshell writes to its log; the lines mentioning this plugin are the useful
ones.

**Is it reproducible from a clean state?**

State lives under `~/.local/state/omarchy/`; deleting this plugin's directory
there is always safe and the next poll rebuilds it. Say whether that changed
anything.
