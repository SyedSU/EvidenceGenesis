EVIDENCE GENESIS - THE FIRST LITTLE WORLD
Windows playable build 0.4.0

START
1. Extract the entire ZIP (right-click > Extract All).
2. Open the extracted EvidenceGenesis folder.
3. Double-click EvidenceGenesis.exe. Wait for "Local AI ready".
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
documents. Previous version 0.2 workshop saves load automatically.

DATA
Autosave: %APPDATA%\EvidenceGenesis\workshop.json
Settings > Open save folder locates your actual save directory.
The save contains lessons, documents, companions and progress. Keep
backups before moving computers. An invalid save is preserved rather
than overwritten. Chats appear for the session; teach a lesson to
make something persistent. All AI requests go to a bundled process
on this computer (127.0.0.1) using a per-launch access key.
Closing the game stops its own AI process.

WHAT THIS BUILD IS
A native, single-workshop companion game with a real bundled local
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
