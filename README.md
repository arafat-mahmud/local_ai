# local_ai

Local AI Flutter app with internal model downloader and updater.

## What It Does

- First launch can download the AI model from your server link.
- The model is installed automatically into app storage.
- App works offline after model installation.
- On later launches, app checks manifest version and shows update option.
- When new model is installed, old model file is deleted automatically.

## Manifest Format

Use the provided [model_manifest.example.json](model_manifest.example.json) format:

```json
{
  "version": "1.0.2",
  "version_code": 3,
  "model_name": "SmolLM2-1.7B-Instruct-Q8_0",
  "file_name": "SmolLM2-1.7B-Instruct-Q8_0.gguf",
  "file_url": "https://drive.google.com/file/d/1krpwv2FV7NQSf07_0l7h3Eozzc0T93wZ/view?usp=sharing",
  "file_size_bytes": 1820414944,
  "notes": "Updated model file link"
}
```

## Run With Your Manifest URL

```bash
flutter run --dart-define=MODEL_MANIFEST_URL="https://drive.google.com/uc?export=download&id=1iRH0TAJsP6wvL9JxWKGOIEdW14A1RxsD"
```

## Google Drive: Which Files To Upload

Upload these 2 files:

1. Model binary file (example: `.gguf`)
2. Manifest JSON file (same structure as `model_manifest.example.json`)

Important:

- Put the model file link inside manifest `file_url`.
- Give the app only the manifest direct-download URL via `MODEL_MANIFEST_URL`.
- Compatibility mode: if you accidentally pass a direct model URL instead of manifest URL, the app can still download/install the model, but versioned update detection is limited until you switch back to manifest URL.

## Release Update Flow

1. Upload new model file to Google Drive.
2. Update manifest `version_code` to a higher number.
3. Update manifest `file_url`, `file_name`, and `file_size_bytes`.
4. Keep same manifest URL.
5. App detects update and offers install.
