# Contributing

Start with [Development](docs/DEVELOPMENT.md) and [Architecture](docs/ARCHITECTURE.md). Use a small issue or pull request with the concrete trigger, resulting behavior, focused validation, and remaining limits. Keep source and tests separate from generated bundles, Python environments and scientific result archives.

Preserve native editor identity, selection and Undo across view changes. Test narrow windows, accessibility preferences and kernel failure paths when changing those areas. New data operations must validate before mutation and retain namespace scope. Live plots should replace one output rather than append every frame; solver callbacks should not change numerical results or copy entire 3D histories.

Run only the checks appropriate to the change, and include their actual commands/results. Use owned temporary files/kernels. Do not close a user's app, rerun a large default simulation, or overwrite existing results for a smoke test. Test standalone Swift mains with the required dependency files rather than compiling every `@main` together.

Do not post credentials, private datasets or unsanitized notebook outputs. Review [Security](SECURITY.md) and [Licensing](LICENSING.md) before submitting code; no additional license grant is implied by this repository's visibility.
