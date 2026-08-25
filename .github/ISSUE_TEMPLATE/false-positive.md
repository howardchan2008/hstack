---
name: A guard fired on ordinary work
about: The failure that gets hooks uninstalled. Becomes an allow-arm test case.
title: "[false positive] <hook>: refused <what>"
labels: false-positive
---

**Which hook**

**What it refused**

<!-- The exact payload. It becomes the allow arm of that guard's test case. -->

```
```

**Why that work was legitimate**

<!-- One or two sentences. What you were doing and why the guard was wrong to
     stop it. -->

**What it printed**

```
```

---

One false positive teaches a bypass, the bypass becomes a habit, and then the
whole hooks directory gets turned off. This is worth reporting even when you
have already worked around it.
