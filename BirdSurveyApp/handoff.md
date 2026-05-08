# BirdSurvey App Handoff

## Current State

Project path:

```text
/Users/wuyang/Github/BirdSurveyApp
```

This is a Flutter app named `bird_survey_app`.

Latest local APK:

```text
/Users/wuyang/Github/BirdSurveyApp/release/BirdSurvey_1.0.6_20260511.apk
```

GitHub push has not succeeded yet because no usable remote repository exists. The current remote in `/Users/wuyang/Github` returned `Repository not found`.

## Main Recent Requirement

The app records bird survey observations. The key requirement is that the same species can have:

- a species-level total count
- independent counts for each per-species custom field

Examples of per-species custom fields:

- `行为`: 觅食, 休息, 飞行, 其他
- `位置`: 泥滩, 水面, 岸边, 其他
- `性别/年龄`: 成鸟, 幼鸟, 其他

These fields must be decoupled. For example, `行为.休息` and `位置.泥滩` must not mirror each other's counts.

## Counting Rules

Species total is independent:

```text
红腹滨鹬 total = 40
```

Each field has its own option counts:

```text
红腹滨鹬 total = 40

行为:
- 觅食 = 1
- 其他 = 39

位置:
- 泥滩 = 1
- 其他 = 39
```

`其他` is calculated per field:

```text
其他 = species total - sum(non-其他 option counts for that field)
```

If allocated field counts exceed species total, species total is raised to fit them.

## UI Interaction Rules

In species tiles:

- Tap species card: species total +1
- Tap count circle: edit species total directly
- Tap a field option chip: that field option count +1
- Long press a field option chip: edit that field option count directly

## Data Model Changes

File:

```text
lib/models/survey_session.dart
```

Added:

```dart
final Map<String, Map<String, Map<String, int>>> speciesFieldCounts;
```

Shape:

```text
ebirdCode -> fieldId -> optionName -> count
```

Example:

```json
{
  "dunlin": {
    "behavior": {
      "觅食": 20,
      "休息": 5
    },
    "location": {
      "泥滩": 18,
      "水面": 7
    }
  }
}
```

Old data compatibility:

- Existing `speciesFields` still loads.
- If `speciesFieldCounts` is empty but old split-entry `speciesFields` exist, the loader tries to migrate those field values into field counts.

## Database Changes

File:

```text
lib/services/database_service.dart
```

Database version bumped:

```text
4 -> 5
```

New column:

```sql
speciesFieldCounts TEXT DEFAULT ''
```

## Provider Logic

File:

```text
lib/providers/survey_provider.dart
```

Important methods:

```dart
Map<String, int> getSpeciesFieldCounts(String ebirdCode, String fieldId)
```

Returns option counts for one species and one field. Dynamically calculates `其他` if that field has an `其他` option.

```dart
void incrementSpeciesFieldOption(
  BirdSpecies species,
  String fieldId,
  String value,
)
```

Increments only that field's option count. Does not affect other fields.

```dart
void setSpeciesFieldOptionCount(
  BirdSpecies species,
  String fieldId,
  String value,
  int count,
)
```

Sets only that field's option count. Handles `其他` by changing the species total to `allocated non-other + other`.

## UI Changes

Files:

```text
lib/widgets/species_tile.dart
lib/screens/survey_screen.dart
```

`QuickField` now carries option counts and handlers for tap/long-press count editing.

## Tide API Changes

File:

```text
lib/services/tide_service.dart
```

Added `TideSource.chaoxi365`.

Settings keys:

```text
chaoxi365_key
chaoxi365_endpoint
```

Default URL template:

```text
https://www.chaoxi365.com/api/tide?lat={lat}&lng={lng}&key={key}
```

Chaoxi365's public page did not expose stable endpoint docs. The app uses a configurable URL template and flexible JSON parsing. Once official docs are available, update the URL template in settings.

Supported placeholders:

```text
{lat}
{lng}
{lon}
{key}
{date}
{timestamp}
```

Settings page includes built-in API key guides for:

- Chaoxi365
- Stormglass
- WorldTides
- Tianditu
- eBird

## Export Requirement Still Pending

The user showed a spreadsheet screenshot and requested exported data include columns like:

```text
县市
地点名称
风电场
经度
纬度
类
生境
海拔
潮高
潮涨/落
时间
结束时间
年
月
日
天气
观察
记录
物种
数量
```

This has not yet been fully implemented.

Recommended next step:

1. Update `ExportService` to output a flat species-record table matching the screenshot.
2. Map `customValues` and selected survey point metadata into those columns.
3. Include `speciesFieldCounts` in export if field-option breakdown is needed.

## Survey Point CSV Requirement Still Pending

The imported CSV may contain:

```text
县市
地点名 / 地点名称
风电场名 / 风电场
```

The user wants filtering by column name.

Current state:

- `SurveyPoint` only stores `name`, `latitude`, `longitude`, `notes`.
- `SurveyPoint.fromCsv` is simple positional CSV parsing.

Recommended implementation:

1. Add metadata to `SurveyPoint`, for example:

```dart
final Map<String, String> attrs;
```

2. Parse CSV by header names.
3. Recognize aliases:

```text
地点名 / 地点名称 / 名称 / name
纬度 / lat / latitude
经度 / lon / lng / longitude
县市
风电场名 / 风电场
```

4. Add filter UI in survey start / survey point management:

```text
筛选列: 县市 / 地点名称 / 风电场 / ...
筛选值: distinct values from that column
```

5. When selecting a survey point, put point attrs into `SurveySession.customValues`, so export can include `县市`, `地点名称`, `风电场`.

## Validation

Latest validation:

```bash
/Users/wuyang/.flutter-sdk/bin/flutter test --no-pub
```

Passed.

```bash
/Users/wuyang/.flutter-sdk/bin/flutter analyze
```

Only remaining issues are pre-existing async context infos:

```text
lib/screens/survey_points_screen.dart:59:19 use_build_context_synchronously
lib/screens/survey_points_screen.dart:60:19 use_build_context_synchronously
```

## Build Notes

Latest build command:

```bash
/Users/wuyang/.flutter-sdk/bin/flutter build apk --release
```

Latest copied APK:

```text
release/BirdSurvey_1.0.6_20260511.apk
```

Signing note:

- Original release keystore was missing.
- A new local release keystore was created for building.
- Do not commit keystores, key properties, passwords, or API keys.
- Devices with an older differently signed APK may need to uninstall the old app before installing this build.

## Git Notes

Root Git repo:

```text
/Users/wuyang/Github
```

`BirdSurveyApp` was originally untracked in that repo and has been added in one local commit. There are unrelated root-level dirty files outside `BirdSurveyApp`; do not include or revert them unless explicitly asked.

Push is pending because there is no valid remote repository.
