# out/checkpoints-kept/ — promoted checkpoint artifacts

`out/checkpoints/` is ignored (taskblock-41 Pass E): a checkpoint run is cheap to regenerate and
its images are large, so they stay on local disk. **The durable record of a checkpoint is the
answers to its checklist**, which belong in `reports/Report-TaskblockN.md`.

Occasionally one image is worth keeping anyway — a reference frame a later change should be
compared against, or the live repro of an open bug. **Copy it here.** This directory is tracked, so
copying the file *is* the decision to keep it; nothing needs `git add -f`, which is the kind of
step that gets forgotten.

Name a promoted file for what it shows and which entry it belongs to
(`br40-01-camera-off-platform.png`), not for the run it came from — run numbers are reused and the
checkpoint that produced it may not exist by the time anyone reads this.
