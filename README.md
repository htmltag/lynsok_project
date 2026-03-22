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
LynSøk isn't just a search engine; it’s a full-stack context pipeline:

**Compact:** Transform a messy folder of PDFs and Docs into a streamlined .lyn archive.

**Index:** Generate a high-density proximity and BM25 index for near-instant lookup.

**Serve:** Expose that knowledge via CLI, REST API, or MCP Server.

---

## 🚀 Quick start

```bash
# Build a LynSok Binary Archive (LYN) from a directory
lynsok -f /path/to/data -o corpus.lyn

# Build the archive + index (fast search)
lynsok -f /path/to/data -o corpus.lyn -x

# Search the archive (uses the index if present)
lynsok search --lyn corpus.lyn --query "your query" --max-results 10
```

If you run via `dart run`, use:

```bash
dart run bin/lynsok.dart search --lyn corpus.lyn --query "your query"
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

### 1) LynSok Archive (`.lyn`)

A `.lyn` file is a compact binary container where each record contains:
- The original file path
- The extracted text (normalized to UTF-8)

This format is designed for fast sequential reads and efficient storage.

### 2) Search Index (`.idx`)

The index is a JSON-based inverted index mapping **token → postings list**.

Each posting includes:
- `docId` (record index in the `.lyn` file)
- `tf` (term frequency)
- `offsets` (list of byte offsets where the term occurs)

Multiple offsets per term allow accurate proximity scoring.

### 3) Search Pipeline (BM25 + Proximity)

When searching:

1. Tokenize the query.
2. Look up postings for each term.
3. Score documents using:
   - **BM25** (relevance ranking)
   - **Proximity boost** (documents in which query terms appear close together rank higher)
4. Extract context-aware snippets around the best match.

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

This repo is focused on a single shared core library (indexing/searching) with multiple interfaces built on top.

```
lynsok/
├── bin/
│   ├── lynsok.dart         # CLI entry point
│   ├── mcp.dart               # MCP-style stdin/stdout JSON server
│   ├── server.dart            # HTTP REST server (shelf)
│   └── llm.dart               # RAG+LLM example (search + query an LLM)
├── lib/
│   ├── lynsok.dart     # Public export surface
│   ├── src/
│   │   ├── config.dart        # Config loader/saver (JSON)
│   │   ├── llm.dart           # LLM helpers (OpenAI/Ollama)
│   │   ├── searcher.dart      # Core search logic (BM25 + proximity)
│   │   ├── utils/
│   │   │   ├── lyn_format.dart
│   │   │   ├── lyn_reader.dart
│   │   │   ├── lyn_index.dart
│   │   │   └── tokenizer.dart
│   │   └── runner.dart        # Compaction / archive creation
├── test/                      # Unit tests
├── pubspec.yaml               # Dependencies and executables
├── analysis_options.yaml
└── .lynsok.json            # Optional config file (created on demand)
```

---

## 🧩 Core + Interfaces

### Core (`lib/`)
The core library contains the shared logic used by all interfaces:
- `.lyn` archive parsing and writing
- Search indexing and BM25 + proximity scoring
- Smart snippet extraction
- Config file handling + LLM settings

### Command-line interface (`bin/lynsok.dart`)
Provides the primary CLI experience for compaction, indexing, and search.

### MCP server (`bin/mcp.dart`)
A stdin/stdout JSON-RPC 2.0 server that speaks the Model Context Protocol (MCP) framing used by tools like Claude Desktop, Cursor, and other MCP clients.

It uses `Content-Length` framing (not newline-delimited JSON) and supports:
- `initialize` (handshake + capabilities)
- `tools/list` (discover available tools)
- `tools/call` (invoke tools such as `search`)
- `$/cancel` (cancel in-flight operations)

Example request (search tool call):

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "tool": "search",
    "args": {
      "query": "your query",
      "max_results": 5
    }
  }
}
```

### REST server (`bin/server.dart`)
A small `shelf` server exposing endpoints like `/search`.

### LLM helper (`bin/llm.dart`)
A helper that performs a search and sends the top results to an LLM (OpenAI / Ollama) using the config.

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
