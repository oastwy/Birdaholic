# Birdaholic · 鸟瘾综合征

Birdaholic is a bird identification learning app for Chinese-speaking birdwatchers and nature education learners. It combines photo and bird song flashcards, quizzes, and regional species lists to help users learn and review local birds.

**As of September 2026, the maintainer estimates approximately 2,000 users.** This is an estimate of the user base, not a monthly active user or monthly download count.

## Download

- [Download page](https://birding.today/download.html): check this page for available platform releases.
- [iOS beta via TestFlight](https://testflight.apple.com/join/RbF8btWg): availability depends on beta capacity and build expiration.

The project includes adaptation and build work for Android, iOS, and OpenHarmony. The current source version is `1.8.0+96`; released and beta versions may differ across platforms.

## Features

- Photo and bird song flashcards, multiple-choice quizzes, and learning and review modes.
- A bundled learning pack featuring 100 common birds of China, usable without an eBird API key.
- Local ZIP data pack import, server pack downloads, and regional per-species downloads. Downloaded media can be used offline.
- Species filtering by country and region. Optional eBird features use the user's own API key.
- Locally stored learning progress, favorites, and flashcard preferences.
- Photo difficulty filters and attribution for photos and recordings.
- Media upload and organization tools for authorized administrators.

## Maintenance and feedback

Ongoing maintenance includes user feedback, media and data pack management, platform compatibility, regression checks, and releases. Recent work has addressed data pack media isolation, recovery from corrupted local storage, audio playback, and error handling.

Please report bugs or request improvements through [GitHub Issues](https://github.com/oastwy/Birdaholic/issues). Include your platform, app version, reproduction steps, and expected behavior. Do not include API keys, administrator tokens, or private information.

## Development

Built with Flutter and Dart. Species lists and media features draw on sources including eBird, Xeno-canto, and iNaturalist.

Application code is in `lib/`, tests are in `test/`, and platform build scripts are in `scripts/`.

The current `pubspec.yaml` includes local paths and dependency overrides for OpenHarmony plugins. These paths are not directly usable in a standard Flutter environment. Review the relevant platform scripts and dependency configuration before building, and provide your own SDK paths and signing materials. Third-party API keys and server administrator credentials are not provided with the source.

## License

Original software source code in this project is licensed under the [MIT License](LICENSE). Use, modification, and commercial distribution are permitted subject to retaining the copyright notice and license text.

Photos, recordings, species lists, data packs, and third-party dependencies retain their respective licenses or terms; the software license does not relicense them. Before reusing or redistributing media, check each item's source, creator, license, and attribution requirements. Some items may restrict commercial use or require sharing adaptations under the same license. Third-party APIs remain subject to their service terms.
