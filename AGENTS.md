# Repository workflow

- Commit completed, coherent changes as you go. Run the checks appropriate to each change before committing, and push the commits to `origin main`.
- Build and install new versions locally as you go. Run `./scripts/build-app.sh`, install the resulting `dist/RocketUp.app` into `/Applications/RocketUp.app`, and register the installed app with macOS. Verify the installed bundle's signature, then remove `dist/RocketUp.app` so the installed copy is the only app bundle left from the build.
