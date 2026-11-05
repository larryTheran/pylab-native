# Security and trust

Notebook cells, imported scripts and console commands run as ordinary Python under your user account. They can read/write accessible files, make network requests and launch processes. Independent Cells separates names within one kernel; it is not a security boundary. Run only code you trust and use normal operating-system controls for untrusted workloads.

The frontend does not execute HTML/JavaScript MIME output. Unsupported rich output is preserved in notebook JSON. NPY export/import does not intentionally enable pickle for unsupported arbitrary objects. Export/import operations validate shapes, names and existing-file conflicts, but scientific libraries and the external environment remain part of the trust boundary.

Never commit passwords, access tokens, `.env` files, signing certificates, provisioning secrets or confidential notebook data. The app has no GitHub-account requirement. A credential accidentally posted publicly should be revoked through its provider.

For a security problem, contact the repository owner through their GitHub profile without including secrets or a public exploit dataset. Use GitHub private vulnerability reporting if that feature is enabled. General reproducible bugs belong in ordinary issues.
