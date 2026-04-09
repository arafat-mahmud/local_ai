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
  "version": "1.0.0",
  "version_code": 1,
  "model_name": "SmolLM2-1.7B-Instruct-Q4_K_M",
  "file_name": "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
  "file_url": "https://drive.google.com/file/d/YOUR_MODEL_FILE_ID/view?usp=sharing",
  "file_size_bytes": 1138166333,
  "notes": "Initial release"
}
```

## Run With Your Manifest URL

```bash
flutter run --dart-define=MODEL_MANIFEST_URL="https://drive.google.com/uc?export=download&id=YOUR_MANIFEST_FILE_ID"
```

## Release Update Flow

1. Upload new model file to Google Drive.
2. Update manifest `version_code` to a higher number.
3. Update manifest `file_url`, `file_name`, and `file_size_bytes`.
4. Keep same manifest URL.
5. App detects update and offers install.
