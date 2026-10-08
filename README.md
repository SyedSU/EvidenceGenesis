# Evidence Genesis

A 2.5D pixel-art companion workshop with editable character memory and real document output.

## Run on Windows

Install Python 3.10 or newer, download or clone this repository, and open a terminal in its folder:

```powershell
python runtime/server.py
```

If Windows uses the Python launcher, use `py runtime/server.py` instead. Open **http://127.0.0.1:8765** in your browser. No pip packages, Node installation, external artwork, or AI service subscription are needed to run template mode.

## First experience

1. Select Milo and click **Use an example lesson**.
2. Teach the preference `format` → `numbered steps`.
3. Open **Create**, enter a title and source notes (one point per line), and make a document.
4. Review and edit the result. Download Markdown or HTML, or print/save PDF through the browser.
5. Approve it to grant document skill progress.
6. Edit the `format` lesson to `bullet points`, then make another document to observe the correction.
7. Feed/rest companions, change their names and roles in Settings, switch the room lighting, or move the plant.

Lessons belong to individual characters. The application saves the workshop in the current browser's local storage. Back up through **Settings & saves → Download backup**. Browser storage can be cleared and is not encrypted. There is no cloud account or synchronization in this build.

## Optional local AI

Run a local model server implementing `/v1/models` and `/v1/chat/completions`, such as [llama.cpp's server](https://github.com/ggml-org/llama.cpp/tree/master/tools/server). Supply a compatible instruct GGUF model separately; model weights are not bundled. Start its server on `127.0.0.1:8080`, then launch Genesis and use **Settings → Check local model**. Select **Local AI** in Create.

Example after installing llama.cpp and downloading a model:

```powershell
llama-server -m "C:\Models\your-instruct-model.gguf" --host 127.0.0.1 --port 8080
```

Optional configuration before launching Genesis:

```powershell
$env:GENESIS_MODEL_URL = "http://127.0.0.1:8080/v1"
# Only set this if your server requires an explicit model identifier:
$env:GENESIS_MODEL = "your-model-id"
python runtime/server.py
```

The bridge sends the selected character, its current lessons, and the task notes to the local model. It does not train model weights, run commands, or silently call a cloud model. Connection failures are shown; your source notes remain available. A changed lesson affects subsequent requests, not documents already produced.

**No real model is bundled or benchmarked yet.** Quality, memory consumption, and latency depend on the model and computer. In template mode, only `format`, `sign-off`, and glossary lessons affect output; arbitrary instructions and roles do not change template behavior. Reviewer behavior is requested only in local AI mode.

## Architecture

- `web/`: responsive browser interface, original procedural pixel art, game state, document review/export.
- `runtime/server.py`: loopback-only static server and local-model bridge (Python standard library).
- `tests/`: game rules and runtime transport tests.
- `docs/`: milestone scope and verification notes.

The first target is a local browser prototype. A desktop installer, mobile application, autonomous scheduling, microphone input, generated asset library, and multi-agent teamwork are future milestones.

## Development checks

Node 20+ is needed for JavaScript checks, not for running the application.

```sh
npm test
npm run check
python -m unittest discover -s tests -p 'test_*.py'
```

## Distribution

This repository currently has no open-source license grant for the original application code or artwork. Review the licenses of any separately selected model and runtime before distributing a commercial bundle. Third-party weights and voices are not included.
