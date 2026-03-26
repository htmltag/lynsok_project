# ⚡ LynSøk (Lyn-Sok)
**Instant, local-first context for AI—without the vector bloat.**

LynSøk (Norwegian for Lightning Search) is a high-performance retrieval engine designed to bridge the gap between massive private document archives and Large Language Models. Built in Dart for native performance, it provides the "Ground Truth" for your AI agents at hardware-accelerated speeds.

## Why LynSøk?
In a world of complex cloud-based vector databases, LynSøk takes a different path: **Extreme efficiency through local indexing.**

🚀 **Native Speed:** Optimized binary seeking and Logical Block Addressing (LBA) allow for sub-second retrieval from gigabyte-scale archives.

🔒 **Privacy by Design:** Your data never leaves your machine. Indexing and retrieval happen entirely on-device.

📦 **The .lyn Format:** A custom, portable binary format that packs raw text and high-speed BM25 metadata into a single, seek-optimized file.

🧠 **Smart Context:** Unlike simple keyword search, LynSøk respects document boundaries, delivering "Smart Chunks" (coherent paragraphs) that LLMs can actually understand.

🔌 **MCP Ready:** Native support for the Model Context Protocol. Connect your private knowledge base to Claude, Cursor, or any modern AI IDE in seconds.

## The Architecture
LynSøk is now organized as a Dart workspace monorepo with shared core logic and multiple app surfaces:

**Core Engine (`packages/lynsok_core`):** Ingestion, extraction, archive format, indexing, search, config, and LLM client integrations.

**Interfaces (`apps/lynsok_cli`):** CLI tools for compaction/search plus REST, MCP, and LLM-oriented entry points.

**Desktop UI (`apps/desktop`):** Flutter desktop app for creating/managing indexes with local metadata persistence.

At runtime, all surfaces use the same pipeline: **ingest -> compact (`.lyn`) -> index (`.idx`) -> retrieve (BM25 + proximity + smart snippets)**.

---

## 🚀 Quick start

From the workspace root (`lynsok_project`):

```bash
# Build a LynSok Binary Archive (LYN) from a directory
dart run apps/lynsok_cli/bin/lynsok.dart -f /path/to/data -o corpus.lyn

# Build the archive + index (fast search)
dart run apps/lynsok_cli/bin/lynsok.dart -f /path/to/data -o corpus.lyn -x

# Search the archive (uses the index if present)
dart run apps/lynsok_cli/bin/lynsok.dart search --lyn corpus.lyn --query "your query" --max-results 10
```

Or from inside `apps/lynsok_cli`:

```bash
cd apps/lynsok_cli
dart run bin/lynsok.dart search --lyn corpus.lyn --query "your query"
```

If you have the executable installed on `PATH`, you can also use:

```bash
lynsok search --lyn corpus.lyn --query "your query"
```

---

## 🧰 CLI Overview

### `compact` mode (default)
Creates a `.lyn` archive containing the extracted text from each input file.

```bash
lynsok -f /path/to/data -o corpus.lyn
```

### `--build-index` (`-x`)
Builds a `.idx` search index alongside the archive.

```bash
lynsok -f /path/to/data -o corpus.lyn -x
```

### `search` subcommand
Search a `.lyn` archive for a query.

```bash
lynsok search --lyn corpus.lyn --query "your query" --max-results 10
```

#### Optional search flags
- `--context-window <bytes>`: how much context to include around each match (default: `1200`).
- `--rag`: bundle the top-N snippets into one single block for feeding an LLM.
- `--rag-separator <text>`: separator used between bundled snippets when `--rag` is enabled.

Example (RAG output):

```bash
lynsok search --lyn corpus.lyn --query "your query" --max-results 5 --rag
```

---

## 🏗 Architecture Overview
### 1) Workspace Modules

```text
lynsok_project/
├── packages/
│   └── lynsok_core/      # Shared engine + data format + search + config
├── apps/
│   ├── lynsok_cli/       # CLI binaries (search, mcp, server, llm)
│   └── desktop/          # Flutter desktop application
└── pubspec.yaml          # Dart workspace definition
```

### 2) Ingestion and Compaction Pipeline

`LynSokRunner` orchestrates ingestion and extraction in parallel:

1. **Connector layer** streams file chunks from a file or directory.
2. **Isolate pool** distributes chunk work across worker isolates.
3. **Extraction worker** normalizes plain text and extracts text from supported binary formats (notably PDF and DOCX).
4. **Archive writer** appends extracted text into `.lyn` records and patches record lengths safely.
5. **Optional index builder** tokenizes each record and emits a `.idx` sidecar index.

### 3) Storage Formats

#### `.lyn` archive (binary)
Record-oriented binary format:

- Magic + version header
- Per-record `STX`
- Source path length + path
- Body length + extracted UTF-8 text bytes
- Per-record `ETX`

This supports compact storage plus deterministic random access to document bodies.

#### `.idx` index (JSON)
Inverted index mapping token -> postings, where each posting stores:

- `docId`
- `tf` (term frequency)
- `offsets` (byte offsets for occurrences)

Document metadata (`path`, body offsets/lengths, token count) is persisted for fast snippet recovery from the archive.

### 4) Retrieval Pipeline

`LynSokSearcher` supports two modes:

- **Indexed search:** BM25 ranking + proximity boost using posting offsets.
- **Raw search fallback:** Full archive scan when no index is available.

Snippets are centered around best match offsets, then expanded to sentence/paragraph boundaries for cleaner RAG context.

### 5) Interface Layer

- **CLI (`apps/lynsok_cli/bin/lynsok.dart`):** compaction, optional index build, and `search` subcommand.
- **MCP server (`apps/lynsok_cli/bin/mcp.dart`):** exposes `lynsok.search` as an MCP tool over stdio.
- **REST server (`apps/lynsok_cli/bin/server.dart`):** provides `/search` and `/health` endpoints.
- **LLM helper (`apps/lynsok_cli/bin/llm.dart`):** retrieves top snippets and forwards context to configured LLM providers.
- **Desktop app (`apps/desktop`):** uses Riverpod + sqflite to manage index entries and trigger core indexing.

---

## 🧠 How snippets are generated

Snippets are not just fixed byte slices. The extractor:

- Locates a match offset (ideally where query terms are closest)
- Expands outward to nearby boundaries:
  - Paragraphs (`\n\n`)
  - Line breaks (`\n`)
  - Sentence endings (`.`, `?`, `!`)
- Avoids cutting in the middle of words by snapping to whitespace if needed

This produces clean, meaningful chunks suitable for human reading and LLM prompts.

---

## 🔍 Search techniques used

### Tokenization
- Normalizes to lowercase.
- Splits on whitespace and punctuation.

### Indexing
- Builds an inverted index storing multiple offsets per term.
- Keeps document length and term frequencies for BM25.

### Ranking
- **BM25** for base relevance scoring.
- **Proximity boost** for documents where query terms appear close together.
- **Snippet extraction** centered on the best proximity match.

---

## 🧪 Project structure
This repository is a multi-package workspace:

```text
.
├── pubspec.yaml
├── packages/
│   └── lynsok_core/
│       ├── lib/
│       │   ├── lynsok_runner.dart
│       │   └── src/
│       │       ├── runner.dart
│       │       ├── searcher.dart
│       │       ├── config.dart
│       │       ├── llm.dart
│       │       ├── connectors/
│       │       ├── core/
│       │       ├── utils/
│       │       └── workers/
│       └── test/
└── apps/
  ├── lynsok_cli/
  │   ├── bin/
  │   │   ├── lynsok.dart
  │   │   ├── mcp.dart
  │   │   ├── server.dart
  │   │   └── llm.dart
  │   └── pubspec.yaml
  └── desktop/
    ├── lib/
    │   ├── screens/
    │   ├── providers/
    │   ├── services/
    │   ├── models/
    │   └── widgets/
    └── pubspec.yaml
```

---

## 🧩 Core + Interfaces
### Core (`packages/lynsok_core`)
Shared logic used by all app surfaces:

- `.lyn` archive write/read utilities
- Chunk ingestion + isolate processing pipeline
- Inverted index build/load (`.idx`)
- Search ranking (BM25 + proximity)
- Smart snippet extraction and highlighting
- Shared config + LLM provider clients

### CLI + Services (`apps/lynsok_cli`)
Operational entry points built on `lynsok_core`:

- `lynsok`: compact, optional index build, and search
- `lynsok_mcp`: MCP tool server exposing search for AI clients
- `lynsok_server`: HTTP API (`/health`, `/search`)
- `lynsok_llm`: retrieval + prompt composition + model call

### Desktop App (`apps/desktop`)
Flutter desktop interface for local index management:

- Riverpod state notifiers for configuration and indexing jobs
- sqflite-based metadata storage of index definitions
- UI flow for creating, browsing, and inspecting local indexes
- Direct use of `LynSokRunner` from the shared core package

---

## ⚙️ Configuration (`.lynsok.json`)

Create a `.lynsok.json` in the working directory to configure defaults. Example:

```json
{
  "lynPath": "corpus.lyn",
  "indexPath": "corpus.lyn.idx",
  "restPort": 8181,
  "llm": {
    "provider": "openai",
    "apiKey": "YOUR_KEY_HERE",
    "model": "gpt-4o",
    "systemPrompt": "You are a helpful assistant. Use provided context to answer questions."
  }
}
```

The CLI and servers read this config automatically (unless overridden by CLI flags).

---

---

## ▶️ Running locally

```bash
dart analyze
dart test
```

---

Happy searching! 🎋
