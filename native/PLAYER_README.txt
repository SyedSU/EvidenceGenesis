EVIDENCE GENESIS - THE FIRST LITTLE WORLD
Windows playable build 0.4.0

START
1. Extract the entire ZIP (right-click > Extract All).
2. Open the extracted EvidenceGenesis folder.
3. Double-click EvidenceGenesis.exe. Choose New Workshop for a new game.
   To bring forward a version 0.2 or 0.3 save, choose Import legacy
   workshop (keep original) from the main menu. This creates a separate
   profile and preserves the original workshop.json and its backup.
4. Continue workshop opens the selected profile on later launches.
   Continue does not automatically import legacy saves. You can play
   in Offline template mode while waiting for "Local AI ready".
Keep brain and model beside the executable. No Unity, editor, Python,
account, API key or internet connection is needed to play this package.
Windows 10/11, 64-bit. Hardware with an OpenGL 3.3 graphics driver is
required. AI speed depends on your CPU; this is a small CPU model.
Allow roughly 2 GB of free disk space while extracting. We have not
measured minimum RAM on your particular laptop. Template mode remains
available while the model starts or if your computer cannot run it.
On a fresh Windows installation, the AI also needs Microsoft's C++
x64 runtime. If the game requests it, open Settings > Download Microsoft
AI support, install the official Microsoft download, then restart.
Official link: https://aka.ms/vc14/vc_redist.x64.exe
This one-time prerequisite needs internet to download and Windows may
request administrator approval. It is not Unity or a development editor.
This independent preview is not code-signed.

PLAY
WASD / arrows: walk. Click ground: walk there. Tab: switch companions.
E: interact with nearby furniture. Escape: close panel / settings.
Teach: use the first lesson or write your own. Memory: edit or forget.
Create: enter a title and notes, choose Local AI or Offline template.
Documents: review, edit, approve, export Markdown or printable HTML.
To make a PDF, open the HTML and choose Print > Save as PDF.
Settings: rename your companion, assign Document maker or Reviewer,
feed a berry, toggle music or lighting, fullscreen, back up or restore.
Rest at the bed. Gather berries at the bush. Approving a document
awards one star. Open Missions to collect six milestone rewards.
Feed and rest your companions, teach lessons, approve work from each,
and build a garden to complete the mission board. Each reward is
collected once. Workshop sells a garden (2 stars), lanterns (3 stars)
and a reading corner (4 stars). Companions level up every three approved
documents. Legacy saves are imported only when you choose the main
menu import action; they are never overwritten by profile autosaves.

DATA
Profile index: %APPDATA%\EvidenceGenesis\profiles.json
Profile autosave: %APPDATA%\EvidenceGenesis\profiles\<id>.json
Original legacy save: %APPDATA%\EvidenceGenesis\workshop.json
Each profile has its own lessons, documents, companions, task history
and progress. Save payloads use version 4 (saveSchema 4). Older game
versions cannot open these profiles; cross-epoch rollback is unsupported.
Settings > Open save folder locates your actual save directory.
Back up the entire EvidenceGenesis directory before changing versions
or moving computers. Import preserves the legacy file and its backup. An invalid save is preserved rather
than overwritten. Chats appear for the session; teach a lesson to
make something persistent. All AI requests go to a bundled process
on this computer (127.0.0.1) using a per-launch access key.
Closing the game stops its own AI process.

WHAT THIS BUILD IS
A native companion game with separate named workshop profiles with a real bundled local
language model. Teaching supplies remembered instructions and
preferences; it does not train new model weights or create AGI.
The small model can make mistakes. Review its documents and replies.
Skills in this build are document creation and note review. Arbitrary
computer automation, voice, multiplayer and mobile builds are not
implemented. Future releases can extend the same game project.

CREDITS
Original procedural artwork and synthesized music for Evidence Genesis.
Godot 4.7.2 stable; llama.cpp b11429; Qwen2.5-0.5B-Instruct Q4_K_M.
See licenses/ for copyright notices. SHA256SUMS.json records packaged
file hashes and the model source. No original third-party game art used.
