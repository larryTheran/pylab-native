# Changelog

## 0.7.3 — Live plots

- Handle Jupyter display IDs and replacement updates, including cross-cell and late linked updates.
- Keep one latest frame shared by inline and already-open figures; preserve figure size and zoom.
- Preserve MIME data/metadata and expression counts; detach unsupported images and reset live links across kernel changes.
- Add a short live plotting example and an end-to-end tiny FDTD pipeline check.
- Integrate with the companion FDTD 3D live-preview runner without changing its numerical update equations.

## 0.7.2 — Execution visibility

Queued/running/input phases, actual elapsed execution time, active cell rim and `In [*]`, tab activity badges, Stop controls, and Reduce Motion support.

## 0.7.1 — Imported script context

Original-script metadata and temporary `__file__`, main-name, argv and sibling-import context while retaining raw IPython execution semantics.

## 0.7.0 — Workflow and editor controls

Persistent project status, kernel CPU/RSS history, metadata-only environment checks, file filtering/drop/import, and editable syntax palette/font/gutter settings.

## Earlier development

0.6 added Shared/Independent cell namespaces and notebook/cell context actions; 0.5 focused on failure recovery and data integrity; 0.4 added the native appearance switch; 0.3 introduced responsive cells, bounded outputs, magnetic tabs and console docking; 0.2 added analysis/search/data tools.

Detailed historical notes and earlier artifact names are retained in [Release history](docs/RELEASE_HISTORY.md). The [validation record](VALIDATION.md) lists checked behaviors and practical limits. Public-repository preparation adds documentation, portable test paths and CI entry points; the 0.7.3 app source remains the same implementation as the validated local build.
